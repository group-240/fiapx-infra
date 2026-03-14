# ============================================================
# DATA SOURCES
# ============================================================
data "aws_availability_zones" "available" {}

data "aws_caller_identity" "current" {}

# ============================================================
# VPC
# ============================================================
resource "aws_vpc" "fiapx" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = { Name = "fiapx-vpc" }
}

resource "aws_internet_gateway" "fiapx" {
  vpc_id = aws_vpc.fiapx.id
  tags   = { Name = "fiapx-igw" }
}

resource "aws_subnet" "public" {
  count                   = 2
  vpc_id                  = aws_vpc.fiapx.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                                        = "fiapx-public-${count.index}"
    "kubernetes.io/role/elb"                    = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_subnet" "private" {
  count             = 2
  vpc_id            = aws_vpc.fiapx.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                                        = "fiapx-private-${count.index}"
    "kubernetes.io/role/internal-elb"           = "1"
    "kubernetes.io/cluster/${var.cluster_name}" = "shared"
  }
}

resource "aws_eip" "nat" {
  count  = 2
  domain = "vpc"
  tags   = { Name = "fiapx-nat-eip-${count.index}" }
}

resource "aws_nat_gateway" "fiapx" {
  count         = 2
  allocation_id = aws_eip.nat[count.index].id
  subnet_id     = aws_subnet.public[count.index].id
  tags          = { Name = "fiapx-nat-${count.index}" }
  depends_on    = [aws_internet_gateway.fiapx]
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.fiapx.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.fiapx.id
  }
  tags = { Name = "fiapx-public-rt" }
}

resource "aws_route_table_association" "public" {
  count          = 2
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  count  = 2
  vpc_id = aws_vpc.fiapx.id
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.fiapx[count.index].id
  }
  tags = { Name = "fiapx-private-rt-${count.index}" }
}

resource "aws_route_table_association" "private" {
  count          = 2
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private[count.index].id
}

# ============================================================
# SECURITY GROUPS
# ============================================================
resource "aws_security_group" "eks_cluster" {
  name        = "fiapx-eks-cluster-sg"
  description = "EKS cluster security group"
  vpc_id      = aws_vpc.fiapx.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "fiapx-eks-cluster-sg" }
}

resource "aws_security_group" "rds" {
  name        = "fiapx-rds-sg"
  description = "RDS security group - allow EKS nodes only"
  vpc_id      = aws_vpc.fiapx.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.eks_cluster.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "fiapx-rds-sg" }
}

# Permite que os nodes EKS (SG managed do cluster) acessem o RDS.
# O cluster_security_group_id é criado pelo EKS automaticamente e associado
# tanto ao control plane quanto aos nodes — diferente do SG adicional acima.
resource "aws_security_group_rule" "rds_from_eks_managed_sg" {
  description              = "Allow EKS cluster/node managed SG to reach RDS on 5432"
  type                     = "ingress"
  from_port                = 5432
  to_port                  = 5432
  protocol                 = "tcp"
  security_group_id        = aws_security_group.rds.id
  source_security_group_id = aws_eks_cluster.fiapx.vpc_config[0].cluster_security_group_id

  depends_on = [aws_eks_cluster.fiapx]
}

# ============================================================
# EKS CLUSTER
# ============================================================
resource "aws_eks_cluster" "fiapx" {
  name     = var.cluster_name
  role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.eks_cluster_role_name}"
  version  = "1.29"

  vpc_config {
    subnet_ids              = concat(aws_subnet.public[*].id, aws_subnet.private[*].id)
    security_group_ids      = [aws_security_group.eks_cluster.id]
    endpoint_public_access  = true
    endpoint_private_access = true
  }
}

resource "aws_eks_node_group" "fiapx" {
  cluster_name    = aws_eks_cluster.fiapx.name
  node_group_name = "fiapx-nodes"
  node_role_arn   = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${var.eks_node_role_name}"
  subnet_ids      = aws_subnet.private[*].id
  instance_types  = [var.node_instance_type]

  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  update_config {
    max_unavailable = 1
  }
}

# ============================================================
# ECR
# ============================================================
resource "aws_ecr_repository" "fiapx" {
  name                 = "fiapx"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_ecr_repository" "fiapx_ms_processing" {
  name                 = "fiapx-ms-processing"
  image_tag_mutability = "MUTABLE"
  force_delete         = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

# ============================================================
# S3
# ============================================================
resource "aws_s3_bucket" "videos" {
  bucket        = var.s3_bucket_name
  force_destroy = true
  tags          = { Name = "fiapx-videos" }
}

resource "aws_s3_bucket_public_access_block" "videos" {
  bucket                  = aws_s3_bucket.videos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "videos" {
  bucket = aws_s3_bucket.videos.id
  versioning_configuration {
    status = "Enabled"
  }
}

# ============================================================
# HELM — RabbitMQ (bitnami)
# ============================================================
resource "helm_release" "rabbitmq" {
  name             = "rabbitmq"
  repository       = "oci://registry-1.docker.io/bitnamicharts"
  chart            = "rabbitmq"
  namespace        = "rabbitmq"
  create_namespace = true
  version          = "16.0.14"
  upgrade_install  = true
  atomic           = true
  cleanup_on_fail  = true
  timeout          = 600

  set = [
    {
      name  = "global.security.allowInsecureImages"
      value = "true"
    },
    {
      name  = "image.registry"
      value = "public.ecr.aws"
    },
    {
      name  = "auth.username"
      value = var.rabbitmq_user
    },
    {
      name  = "auth.password"
      value = var.rabbitmq_password
    },
    {
      name  = "metrics.enabled"
      value = "true"
    },
    {
      name  = "metrics.serviceMonitor.enabled"
      value = "true"
    },
    {
      name  = "metrics.serviceMonitor.namespace"
      value = "monitoring"
    },
    {
      name  = "persistence.enabled"
      value = "false"
    }
  ]

  depends_on = [
    aws_eks_node_group.fiapx,
    helm_release.prometheus_stack
  ]
}

# ============================================================
# RDS PostgreSQL
# ============================================================
resource "aws_db_subnet_group" "fiapx" {
  name       = "fiapx-db-subnet-group"
  subnet_ids = aws_subnet.private[*].id
}

resource "aws_db_instance" "postgres" {
  identifier              = "fiapx-postgres"
  engine                  = "postgres"
  engine_version          = "15"
  instance_class          = "db.t3.micro"
  allocated_storage       = 20
  db_name                 = var.db_name
  username                = var.db_username
  password                = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.fiapx.name
  vpc_security_group_ids  = [aws_security_group.rds.id]
  skip_final_snapshot     = true
  deletion_protection     = false
  publicly_accessible     = false
  backup_retention_period = 7
}

# ============================================================
# HELM — ingress-nginx
# ============================================================
resource "helm_release" "ingress_nginx" {
  name             = "ingress-nginx"
  repository       = "https://kubernetes.github.io/ingress-nginx"
  chart            = "ingress-nginx"
  namespace        = "ingress-nginx"
  create_namespace = true
  version          = "4.9.1"

  set = [
    {
      name  = "controller.service.type"
      value = "LoadBalancer"
    },
    {
      name  = "controller.service.annotations.service\\.beta\\.kubernetes\\.io/aws-load-balancer-type"
      value = "nlb"
    }
  ]

  depends_on = [aws_eks_node_group.fiapx]
}

# ============================================================
# HELM — Prometheus + Grafana (kube-prometheus-stack)
# ============================================================
resource "helm_release" "prometheus_stack" {
  name             = "prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "monitoring"
  create_namespace = true
  version          = "57.2.0"

  set = [
    {
      name  = "grafana.adminPassword"
      value = "fiapx-grafana"
    },
    {
      name  = "grafana.service.type"
      value = "ClusterIP"
    },
    # Necessário para o Grafana funcionar corretamente sob sub-path /grafana via ingress
    {
      name  = "grafana.grafana\\.ini.server.root_url"
      value = "%(protocol)s://%(domain)s/grafana/"
    },
    {
      name  = "grafana.grafana\\.ini.server.serve_from_sub_path"
      value = "true"
    },
    {
      name  = "prometheus.prometheusSpec.serviceMonitorSelectorNilUsesHelmValues"
      value = "false"
    }
  ]

  depends_on = [aws_eks_node_group.fiapx]
}

# ============================================================
# IRSA (LabRole) - OIDC Provider + Trust Relationship
# ============================================================
# Objetivo: permitir que ServiceAccounts do namespace fiapx
# assumam a LabRole via AssumeRoleWithWebIdentity.

data "tls_certificate" "eks_oidc" {
  count = var.enable_irsa ? 1 : 0
  url = aws_eks_cluster.fiapx.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  count            = var.enable_irsa ? 1 : 0
  url             = aws_eks_cluster.fiapx.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.eks_oidc[0].certificates[0].sha1_fingerprint]

  tags = {
    Name = "fiapx-eks-oidc"
  }

  depends_on = [aws_eks_cluster.fiapx]
}

data "aws_iam_policy_document" "labrole_irsa_trust" {
  count = var.enable_irsa ? 1 : 0
  statement {
    sid    = "AllowEKSIRSAForFiapxNamespace"
    effect = "Allow"

    actions = [
      "sts:AssumeRoleWithWebIdentity"
    ]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(aws_eks_cluster.fiapx.identity[0].oidc[0].issuer, "https://", "")}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringLike"
      variable = "${replace(aws_eks_cluster.fiapx.identity[0].oidc[0].issuer, "https://", "")}:sub"
      values = [
        "system:serviceaccount:fiapx:fiapx-processing-sa",
        "system:serviceaccount:fiapx:fiapx-sa"
      ]
    }
  }
}

# AWS Academy não permite criar role nova em muitos cenários.
# Então atualizamos a trust policy da role existente (LabRole).
resource "terraform_data" "update_labrole_trust" {
  count = var.enable_irsa ? 1 : 0
  triggers_replace = [
    aws_iam_openid_connect_provider.eks[0].arn,
    data.aws_iam_policy_document.labrole_irsa_trust[0].json
  ]

  provisioner "local-exec" {
    command = "aws iam update-assume-role-policy --role-name LabRole --policy-document '${data.aws_iam_policy_document.labrole_irsa_trust[0].json}'"
  }

  depends_on = [aws_iam_openid_connect_provider.eks[0]]
}
