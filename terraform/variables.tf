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

variable "sqs_queue_name" {
  description = "SQS FIFO queue name"
  type        = string
  default     = "fiapx-processing.fifo"
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
