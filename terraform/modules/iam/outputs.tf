output "eks_cluster_role_arn" {
  value = aws_iam_role.eks_cluster.arn
}

output "app_workload_role_arn" {
  value = aws_iam_role.app_workload.arn
}
