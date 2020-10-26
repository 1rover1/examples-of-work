variable "bucket_name" {
    default = "this-is-my-picture-bucket"
}

variable "domain_names" {
    type = list
    default = [
        "my.example.com"
    ]
}

variable "acm_certificate" {
    type = string
    default = "arn:aws:acm:us-east-1:124091754394:certificate/38e91762-796e-461f-bf5a-ab623a416add"
}

variable "s3_origin_id" {
    type = string
    default = "myS3Origin"
}

variable "index_document" {
    type = string
    default = "index.html"
}

variable "error_document" {
    type = string
    default = "error.html"
}
