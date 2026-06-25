resource "aws_sqs_queue" "sqs_queue_url_shortener" {
  name                       = var.sqs_queue_name
  visibility_timeout_seconds = 60
  message_retention_seconds  = 86400
  receive_wait_time_seconds  = 20
}