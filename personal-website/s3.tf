data "aws_iam_policy_document" "picture_bucket_policy_document" {
	statement {
		sid = "AllowCloudFront"
		effect = "Allow"
		principals {
			type = "AWS"
			identifiers = [aws_cloudfront_origin_access_identity.origin_access_identity.iam_arn]
		}
		actions = ["s3:GetObject"]
		resources = ["${aws_s3_bucket.picture_bucket.arn}/*"]
	}
}

resource "aws_s3_bucket" "picture_bucket" {
    acl = "private"
}

resource "aws_s3_bucket_public_access_block" "picture_bucket_access_block" {
  bucket = aws_s3_bucket.picture_bucket.id

  block_public_acls   = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_policy" "picture_bucket_policy" {
  bucket = aws_s3_bucket.picture_bucket.id
  policy = data.aws_iam_policy_document.picture_bucket_policy_document.json
}

resource "aws_s3_bucket_notification" "upload_notification" {
  bucket = aws_s3_bucket.picture_bucket.id

  lambda_function {
    lambda_function_arn = aws_lambda_function.upload_handler.arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }
  depends_on = [aws_lambda_permission.allow_bucket]
}
