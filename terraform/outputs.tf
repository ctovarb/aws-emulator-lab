output "vpc_id" {
  value = module.network.vpc_id
}

output "s3_bucket_name" {
  value = module.data.s3_bucket_name
}

output "dynamodb_table_name" {
  value = module.data.dynamodb_table_name
}

output "sqs_queue_url" {
  value = module.data.sqs_queue_url
}

output "secret_name" {
  value = module.data.secret_name
}

output "app_workload_role_arn" {
  value = module.iam.app_workload_role_arn
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}
