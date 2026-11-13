module "network" {
  source = "./modules/network"

  project_name = var.project_name
  environment  = var.environment
  vpc_cidr     = var.vpc_cidr
}

module "data" {
  source = "./modules/data"

  project_name = var.project_name
  environment  = var.environment
}

module "iam" {
  source = "./modules/iam"

  project_name       = var.project_name
  environment        = var.environment
  aws_region         = var.aws_region
  s3_bucket_arn      = module.data.s3_bucket_arn
  dynamodb_table_arn = module.data.dynamodb_table_arn
  sqs_queue_arn      = module.data.sqs_queue_arn
  secret_arn         = module.data.secret_arn
}

module "eks" {
  source = "./modules/eks"

  project_name      = var.project_name
  environment       = var.environment
  cluster_role_arn  = module.iam.eks_cluster_role_arn
  subnet_ids        = module.network.private_subnet_ids
  security_group_id = module.network.app_security_group_id
}
