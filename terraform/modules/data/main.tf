# 1. Bucket S3 con versionado, cifrado y bloqueo de acceso público
resource "aws_s3_bucket" "documents" {
  bucket        = "${var.project_name}-${var.environment}-documents"
  force_destroy = true

  tags = {
    Name = "${var.project_name}-${var.environment}-documents"
  }
}

resource "aws_s3_bucket_versioning" "documents" {
  bucket = aws_s3_bucket.documents.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "documents" {
  bucket = aws_s3_bucket.documents.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 2. Tabla DynamoDB con GSI, PITR y cifrado
resource "aws_dynamodb_table" "orders" {
  name         = "${var.project_name}-${var.environment}-orders"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "order_id"

  attribute {
    name = "order_id"
    type = "S"
  }

  attribute {
    name = "customer_id"
    type = "S"
  }

  attribute {
    name = "created_at"
    type = "S"
  }

  global_secondary_index {
    name            = "CustomerOrdersIndex"
    hash_key        = "customer_id"
    range_key       = "created_at"
    projection_type = "ALL"
  }

  point_in_time_recovery {
    enabled = true
  }

  server_side_encryption {
    enabled = true
  }

  tags = {
    Name = "${var.project_name}-${var.environment}-orders"
  }
}

# 3. Colas SQS: Dead-Letter Queue (DLQ) + Cola Principal con Redrive Policy
resource "aws_sqs_queue" "orders_dlq" {
  name                      = "${var.project_name}-${var.environment}-orders-dlq"
  message_retention_seconds = 1209600 # 14 días
  sqs_managed_sse_enabled   = true

  tags = {
    Name = "${var.project_name}-${var.environment}-orders-dlq"
  }
}

resource "aws_sqs_queue" "orders_main" {
  name                       = "${var.project_name}-${var.environment}-orders-queue"
  visibility_timeout_seconds = 60
  sqs_managed_sse_enabled    = true

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.orders_dlq.arn
    maxReceiveCount     = 3
  })

  tags = {
    Name = "${var.project_name}-${var.environment}-orders-queue"
  }
}

# 4. Secrets Manager para configuración sensible de la aplicación
resource "aws_secretsmanager_secret" "app_config" {
  name                    = "${var.project_name}/${var.environment}/app-config"
  recovery_window_in_days = 0

  tags = {
    Name = "${var.project_name}-${var.environment}-secret"
  }
}

resource "aws_secretsmanager_secret_version" "app_config" {
  secret_id = aws_secretsmanager_secret.app_config.id
  secret_string = jsonencode({
    payment_gateway_api_key = "sk_local_emulated_9988776655"
    webhook_signing_secret  = "whsec_emulated_secret_value"
    max_order_retry         = 3
  })
}
