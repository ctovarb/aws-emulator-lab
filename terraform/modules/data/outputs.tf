output "s3_bucket_name" {
  value = aws_s3_bucket.documents.id
}

output "s3_bucket_arn" {
  value = aws_s3_bucket.documents.arn
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.orders.name
}

output "dynamodb_table_arn" {
  value = aws_dynamodb_table.orders.arn
}

output "sqs_queue_url" {
  value = aws_sqs_queue.orders_main.url
}

output "sqs_queue_arn" {
  value = aws_sqs_queue.orders_main.arn
}

output "sqs_dlq_arn" {
  value = aws_sqs_queue.orders_dlq.arn
}

output "secret_arn" {
  value = aws_secretsmanager_secret.app_config.arn
}

output "secret_name" {
  value = aws_secretsmanager_secret.app_config.name
}
