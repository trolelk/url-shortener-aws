output "file_processor_name" {
  value = aws_lambda_function.lambda_file_processor.function_name
}

output "url_worker_name" {
  value = aws_lambda_function.lambda_url_worker.function_name
}