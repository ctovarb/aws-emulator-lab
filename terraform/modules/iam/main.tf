# 1. Rol IAM para el plano de control de EKS
data "aws_iam_policy_document" "eks_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "eks_cluster" {
  name               = "${var.project_name}-${var.environment}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.eks_assume_role.json
}

resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  role       = aws_iam_role.eks_cluster.name
}

# 2. Rol IAM para la aplicación (IRSA / Workload Identity)
data "aws_iam_policy_document" "app_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com", "ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "app_workload" {
  name               = "${var.project_name}-${var.environment}-app-role"
  assume_role_policy = data.aws_iam_policy_document.app_assume_role.json
}

# 3. Política IAM de mínimo privilegio (Datos + Bedrock Converse API)
data "aws_iam_policy_document" "app_permissions" {
  statement {
    sid    = "S3DocumentsAccess"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:ListBucket"
    ]
    resources = [
      var.s3_bucket_arn,
      "${var.s3_bucket_arn}/*"
    ]
  }

  statement {
    sid    = "DynamoDBOrdersAccess"
    effect = "Allow"
    actions = [
      "dynamodb:PutItem",
      "dynamodb:GetItem",
      "dynamodb:UpdateItem",
      "dynamodb:Query"
    ]
    resources = [
      var.dynamodb_table_arn,
      "${var.dynamodb_table_arn}/index/*"
    ]
  }

  statement {
    sid    = "SQSOrdersQueueAccess"
    effect = "Allow"
    actions = [
      "sqs:SendMessage",
      "sqs:ReceiveMessage",
      "sqs:DeleteMessage",
      "sqs:GetQueueAttributes"
    ]
    resources = [var.sqs_queue_arn]
  }

  statement {
    sid    = "SecretsManagerReadConfig"
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [var.secret_arn]
  }

  statement {
    sid    = "BedrockConverseReview"
    effect = "Allow"
    actions = [
      "bedrock:InvokeModel",
      "bedrock:InvokeModelWithResponseStream"
    ]
    resources = [
      "arn:aws:bedrock:${var.aws_region}::foundation-model/anthropic.claude-3-5-sonnet-20241022-v2:0",
      "arn:aws:bedrock:${var.aws_region}::foundation-model/amazon.nova-pro-v1:0"
    ]
  }
}

resource "aws_iam_policy" "app_permissions" {
  name        = "${var.project_name}-${var.environment}-app-policy"
  description = "Politica de minimo privilegio para S3, DynamoDB, SQS, Secrets Manager y Bedrock"
  policy      = data.aws_iam_policy_document.app_permissions.json
}

resource "aws_iam_role_policy_attachment" "app_permissions" {
  role       = aws_iam_role.app_workload.name
  policy_arn = aws_iam_policy.app_permissions.arn
}
