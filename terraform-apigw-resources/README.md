# Optimising AWS API Gateway for Scale in Terraform: Gateway Resources

## Summary

Improve your life by defining API Gateway resources by listing full paths rather than path parts in a dependency tree.

## Background

Defining API Gateway Resources is essentially the process of mapping out the tree-like structure of endpoints that an API can respond to.

For example:
```
https://api.example.com/things
                       /things/{id}
                       /things/{id}/foo
                       /stuff
```

AWS - and by extension Terraform, require you to map these parts out individually by defining a path part and its parent:

```
resource "aws_api_gateway_resource" "things" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  parent_id   = aws_api_gateway_rest_api.example.root_resource_id
  path_part   = "things"
}

resource "aws_api_gateway_resource" "things-id" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  parent_id   = aws_api_gateway_resource.things.id
  path_part   = "{id}"
}

resource "aws_api_gateway_resource" "things-id-foo" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  parent_id   = aws_api_gateway_resource.things-id.id
  path_part   = "foo"
}

resource "aws_api_gateway_resource" "stuff" {
  rest_api_id = aws_api_gateway_rest_api.example.id
  parent_id   = aws_api_gateway_rest_api.example.root_resource_id
  path_part   = "stuff"
}
```

This works okay for small and relatively static API's but once you start to scale up (in terms of project contributors or number of API endpoints) making changes to resources can become tricky:

* Naming standards for resources can help. In the above example I'm basically including the directory structure in the resource name (see `things-id-foo`) so that I don't clash with another endpoint that named foo.
* Mapping out individual path parts is not self-documenting and you need to build up at least part of the tree in your head to work with it.
* This whole process is slower or more complicated than it needs to be.

Our largest API at work contains around 350 path parts and has dozens of contributors. The code I've explored here is an attempt to address some of the issues faced. 

## Starting at the End

I think it would be much easier for developers to contribute to an API if they only had to modify a list. Resource naming isn't even a thought and there's visual representation of how the API will look:

```
  resources = [
    "pets",
    "pets/{id}",
    "pets/{id}/name",
    "pets/{id}/type",
  ]
```

## Working Backwards

To be able to define resources I'll need to munge the starting data so that I have readily available the path part and the full path to that directory:

```
  # A temporary list where the resource paths have been broken up into lists
  # e.g. [
  #  ["pets"],
  #  ["pets","{id}"],
  # etc
  resources_arrays = [for r in local.resources: split("/", r)]

  resources_paths = [for r in local.resources_arrays: {
    "full_path" = join("/", r)
    "path_part" = r[length(r)-1]
    "parent"    = join("/", slice(r, 0, length(r)-1))
  }]
```

So that gets us the following:
```
resources_paths = [
  {
    "full_path" = "pets"
    "parent" = ""
    "path_part" = "pets"
  },
  {
    "full_path" = "pets/{id}"
    "parent" = "pets"
    "path_part" = "{id}"
  },
  {
    "full_path" = "pets/{id}/name"
    "parent" = "pets/{id}"
    "path_part" = "name"
  },
  {
    "full_path" = "pets/{id}/type"
    "parent" = "pets/{id}"
    "path_part" = "type"
  },
]
```

## The First Attempt

The theory of it seemed pretty solid: it's an array of resources where it recursively sets the parent ID based on either the API Gateway root resource ID or a resource that already exists in the array.

```
resource "aws_api_gateway_resource" "directory_resource" {
  for_each = {for x in local.resources_paths: x.full_path => x}

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = (each.value.parent == "" ?
    aws_api_gateway_rest_api.this.root_resource_id :
    aws_api_gateway_resource.directory_resource[each.value.parent].id
  )
  path_part   = each.value.path_part
}
```

But unfortunately it didn't work. Terraform will panic at at the self-referencing resource and fail with the following error:

```
│ Error: Cycle: aws_api_gateway_resource.directory_resource["pets/{id}/type"], aws_api_gateway_resource.directory_resource["pets/{id}"], aws_api_gateway_resource.directory_resource["pets"], aws_api_gateway_resource.directory_resource["pets/{id}/name"]
```

## The Second Attempt

Saddened but undefeated, I imagined a setup where resources were defined by their subdirectory *depth*.

Adding `directory_depth` to the pre-calculated info:

```
  resources_paths = [for r in local.resources_arrays: {
    "full_path"       = join("/", r)
    "path_part"       = r[length(r)-1]
    "parent"          = join("/", slice(r, 0, length(r)-1))
    "directory_depth" = length(r) - 1
  }]
```


Setting the root level was pretty easy and we only want to do this for resource on the root or top level directory (`directory_depth == 0`):

```
resource "aws_api_gateway_resource" "directory_depth_1" {
  for_each = {for x in local.resources_paths: x.full_path => x if x.directory_depth == 0}

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = each.value.path_part
}
```

Now for the next level we tweak the resource name, `for_each` condition and `parent_id` accordingly:
```
resource "aws_api_gateway_resource" "directory_depth_2" {
  for_each = {for x in local.resources_paths: x.full_path => x if x.directory_depth == 1}

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.directory_depth_1[each.value.parent].id
  path_part   = each.value.path_part
}
```

Add as many as you like depending on how many levels deep you wish to go. You could pre-define 20 levels and if they never get used then so be it.


## Logic Issue

Obviously, having to map each depth like this is not ideal - when you go beyond the depth you've defined what happens? The condition in the resource on `x.directory_depth` is never met and the new resources are silently ignored.

Unless we add in some error handling.

First let's define local variables to help
```
  # How many aws_api_gateway_resource resource levels have been defined. e.g. /foo/bar/baz is 2 subdirs (baz isn't a directory)
  directory_depth_available = 2

  # Dig through our resources and find the deepest value
  directory_depth_used      = max(([for r in local.resources_arrays: length(r) - 1])...)
```

At the time of writing Terraform (v1.0.x) doesn't have an official way to raise errors so I'm using the following:

```
resource "null_resource" "directory_depth_check" {
  count = local.directory_depth_used <= local.directory_depth_available ? 0 : "Directory depth has been exceeded! You will need to add more APIGW directory_depth resources."
}
```

Given an additional API path to force this error

```
  resources = [
    "pets",
    "pets/{id}",
    "pets/{id}/name",
    "pets/{id}/type",
    "pets/{id}/type/foo/bar/baz",
  ]
```

It's a bit hacky but works well if your message and variable names are descriptive enough: 
```
│ Error: Incorrect value type
│ 
│   on stack.tf line 7, in resource "null_resource" "directory_depth_check":
│    7:   count = local.directory_depth_used <= local.directory_depth_available ? 0 : "Directory depth has been exceeded! You will need to add more APIGW directory_depth resources."
│     ├────────────────
│     │ local.directory_depth_available is 2
│     │ local.directory_depth_used is 5
│ 
│ Invalid expression value: a number is required.
```

## Conclusion

As noted above defining each directory depth is not ideal. However in a large project it's probably only 10-15 resources definitions maximum and with error handling implemented it should save a lot of time in the long run.

I only wish I'd implemented this earlier at work :)