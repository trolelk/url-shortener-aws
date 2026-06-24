resource "aws_dynamodb_table" "dynamo_db_table_urls" {
  name = "urls"
  hash_key = "code"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "code"
    type = "S"
  }
}

resource "aws_dynamodb_table" "dynamo_db_table_files" {
  name = "files"
  hash_key = "file_key"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "file_key"
    type = "S"
  }
}