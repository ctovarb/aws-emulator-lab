provider "aws" {
  region = var.aws_region

  # Requerido para evitar reescrituras de host (bucket.127.0.0.1) y timeouts de metadatos
  s3_use_path_style           = true
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true

  default_tags {
    tags = {
      Project     = var.project_name
      Environment = var.environment
      ManagedBy   = "Terraform"
    }
  }
}
