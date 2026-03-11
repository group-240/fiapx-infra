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

output "rabbitmq_host" {
  description = "RabbitMQ service hostname inside EKS"
  value       = "rabbitmq.rabbitmq.svc.cluster.local"
}

output "s3_bucket_name" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.videos.bucket
}

output "rds_endpoint" {
  description = "RDS PostgreSQL endpoint (host:port)"
  value       = aws_db_instance.postgres.endpoint
}

output "rds_host" {
  description = "RDS PostgreSQL hostname only (without port)"
  value       = aws_db_instance.postgres.address
}

output "aws_region" {
  description = "AWS region"
  value       = var.aws_region
}

