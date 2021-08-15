resource "aws_api_gateway_rest_api" "this" {
  name        = "My Pet Store"
  description = "This is my API for demonstration purposes"
}

resource "null_resource" "directory_depth_check" {
  count = local.directory_depth_used <= local.directory_depth_available ? 0 : "Directory depth has been exceeded! You will need to add more APIGW directory_depth resources."
}

resource "aws_api_gateway_resource" "directory_depth_1" {
  for_each = { for x in local.resources_paths : x.full_path => x if x.directory_depth == 0 }

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_rest_api.this.root_resource_id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_resource" "directory_depth_2" {
  for_each = { for x in local.resources_paths : x.full_path => x if x.directory_depth == 1 }

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.directory_depth_1[each.value.parent].id
  path_part   = each.value.path_part
}

resource "aws_api_gateway_resource" "directory_depth_3" {
  for_each = { for x in local.resources_paths : x.full_path => x if x.directory_depth == 2 }

  rest_api_id = aws_api_gateway_rest_api.this.id
  parent_id   = aws_api_gateway_resource.directory_depth_2[each.value.parent].id
  path_part   = each.value.path_part
}

locals {
  resources = [
    "pets",
    "pets/{id}",
    "pets/{id}/name",
    "pets/{id}/type",
    # "pets/{id}/type/foo/bar/baz",    # uncomment this to test breakage
  ]

  resources_arrays = [for r in local.resources : split("/", r)]

  resources_paths = [for r in local.resources_arrays : {
    "full_path"       = join("/", r)
    "path_part"       = r[length(r) - 1]
    "parent"          = join("/", slice(r, 0, length(r) - 1))
    "directory_depth" = length(r) - 1
  }]

  directory_depth_available = 2
  directory_depth_used      = max(([for r in local.resources_arrays : length(r) - 1])...)
}
