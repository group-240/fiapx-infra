variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "fiapx-cluster"
}

variable "eks_cluster_role_name" {
  description = "IAM role name for EKS cluster execution (AWS Academy LabRole)"
  type        = string
  default     = "LabRole"
}

variable "eks_node_role_name" {
  description = "IAM role name for EKS node group execution (AWS Academy LabRole)"
  type        = string
  default     = "LabRole"
}

variable "db_username" {
  description = "RDS master username"
  type        = string
  default     = "fiapx"
}

variable "db_password" {
  description = "RDS master password"
  type        = string
  sensitive   = true
}

variable "db_name" {
  description = "RDS database name"
  type        = string
  default     = "fiapx"
}

variable "s3_bucket_name" {
  description = "S3 bucket for videos and ZIPs"
  type        = string
  default     = "fiapx-videos-bucket"
}

variable "rabbitmq_user" {
  description = "RabbitMQ admin username"
  type        = string
  default     = "admin"
}

variable "rabbitmq_password" {
  description = "RabbitMQ admin password"
  type        = string
  sensitive   = true
}

variable "node_instance_type" {
  description = "EC2 instance type for EKS nodes"
  type        = string
  default     = "t3.medium"
}

variable "node_min_size" {
  type    = number
  default = 1
}

variable "node_max_size" {
  type    = number
  default = 3
}

variable "node_desired_size" {
  type    = number
  default = 2
}

variable "enable_irsa" {
  description = "Enable IRSA resources (OIDC provider + LabRole trust update). Disable in AWS Academy accounts that deny IAM OIDC/trust changes."
  type        = bool
  default     = false
}
