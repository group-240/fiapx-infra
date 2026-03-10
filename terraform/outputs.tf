output "eks_cluster_name" {
  description = "EKS cluster name"
  value       = aws_eks_cluster.fiapx.name
}

output "eks_cluster_endpoint" {
  description = "EKS cluster endpoint"
  value       = aws_eks_cluster.fiapx.endpoint
}

output "ecr_fiapx_url" {
  description = "ECR URL for fiapx service"
  value       = aws_ecr_repository.fiapx.repository_url
}

output "ecr_processing_url" {
  description = "ECR URL for fiapx-ms-processing service"
  value       = aws_ecr_repository.fiapx_ms_processing.repository_url
}

output "sqs_queue_url" {
  description = "SQS FIFO queue URL"
  value       = aws_sqs_queue.processing.url
}

output "sqs_dlq_url" {
  description = "SQS dead-letter queue URL"
  value       = aws_sqs_queue.processing_dlq.url
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.videos.bucket
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

output "irsa_role_arn" {
  description = "IAM role ARN for K8s service account (IRSA)"
  value       = aws_iam_role.fiapx_irsa.arn
}
