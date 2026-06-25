data "archive_file" "file_processor" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/file_processor"
  output_path = "${path.module}/file_processor.zip"
}

data "archive_file" "url_worker" {
  type        = "zip"
  source_dir  = "${path.root}/../lambda/url_worker"
  output_path = "${path.module}/url_worker.zip"
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "lambda.amazonaws.com"
        }
    }]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda-policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["sqs:SendMessage", "sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["dynamodb:PutItem", "dynamodb:GetItem", "dynamodb:UpdateItem"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup", "logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "lambda_file_processor" {
  function_name    = "file-processor"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.file_processor.output_path
  handler          = "handler.handler"
  source_code_hash = data.archive_file.file_processor.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      DYNAMODB_TABLE = "files"
      SQS_QUEUE_URL  = var.sqs_queue_url
    }
  }
}

resource "aws_lambda_function" "lambda_url_worker" {
  function_name    = "url-worker"
  role             = aws_iam_role.lambda_role.arn
  filename         = data.archive_file.url_worker.output_path
  handler          = "handler.handler"
  source_code_hash = data.archive_file.url_worker.output_base64sha256
  runtime          = "python3.12"

  environment {
    variables = {
      DYNAMODB_TABLE = "files"
    }
  }
}

resource "aws_lambda_permission" "s3_invoke" {
  statement_id  = "AllowS3Invoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.lambda_file_processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = var.s3_bucket_arn
}

resource "aws_s3_bucket_notification" "s3_trigger" {
  bucket = var.s3_bucket_id

  lambda_function {
    lambda_function_arn = aws_lambda_function.lambda_file_processor.arn
    events              = ["s3:ObjectCreated:*"]
  }

  depends_on = [aws_lambda_permission.s3_invoke]
}

resource "aws_lambda_event_source_mapping" "sqs_trigger" {
  event_source_arn = var.sqs_queue_arn
  function_name    = aws_lambda_function.lambda_url_worker.arn
  batch_size       = 5
}