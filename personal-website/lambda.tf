data "archive_file" "init" {
  type        = "zip"
  source_dir  = "lambda/"
  output_path = "temp/lambda.zip"
}

data "aws_iam_policy_document" "sdfsdf" {
  statement {
    sid = "1"

    actions = [
      "s3:GetObject",
      "s3:PutObject",
    ]

    resources = [
      "${aws_s3_bucket.picture_bucket.arn}/*"
    ]
  }
}

resource "aws_iam_role" "lambda_execution_role" {
  name = "lambda_execution_role"

  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "lambda.amazonaws.com"
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "lambda_basic_execution_policy" {
  role       = aws_iam_role.lambda_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "bucket_access_policy" {
  name   = "BucketAccessPolicy"
  role   = aws_iam_role.lambda_execution_role.name
  policy = data.aws_iam_policy_document.sdfsdf.json
}

resource "aws_lambda_permission" "allow_bucket" {
  statement_id  = "AllowExecutionFromS3Bucket"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.upload_handler.arn
  principal     = "s3.amazonaws.com"
  source_arn    = aws_s3_bucket.picture_bucket.arn
}

resource "aws_lambda_function" "upload_handler" {
  filename         = "temp/lambda.zip"
  source_code_hash = filebase64sha256("temp/lambda.zip")
  function_name    = "photo_upload_handler"
  role             = aws_iam_role.lambda_execution_role.arn
  handler          = "lambda.handler"
  runtime          = "python3.8"
}
