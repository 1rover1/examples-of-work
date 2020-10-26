resource "aws_cloudfront_origin_access_identity" "origin_access_identity" {}

resource "aws_cloudfront_distribution" "s3_distribution" {
  origin {
    domain_name = aws_s3_bucket.picture_bucket.bucket_regional_domain_name
    origin_id   = var.s3_origin_id
    origin_path = "/website"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.origin_access_identity.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = var.index_document

  aliases = var.domain_names

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = var.s3_origin_id

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 31104000    # 360 days
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    #   locations        = ["US", "CA", "GB", "DE"]
    }
  }

  price_class = "PriceClass_100"

  viewer_certificate {
    acm_certificate_arn = var.acm_certificate
    ssl_support_method = "sni-only"
    minimum_protocol_version = "TLSv1.2_2019"
  }
}
