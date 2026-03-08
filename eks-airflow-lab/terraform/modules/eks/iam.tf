# =============================================================================
# modules/eks/iam.tf
# Cria as IAM Roles e anexa as Policies necessárias para dois atores:
#
#   1. Control Plane do EKS (aws_iam_role.cluster)
#      A AWS precisa desta role para gerenciar recursos em seu nome:
#      criar ENIs, registrar nodes, resolver DNS, etc.
#
#   2. Nodes EC2 do Node Group (aws_iam_role.node)
#      Os nodes precisam desta role para:
#      - Registrar-se no cluster EKS
#      - Fazer pull de imagens do ECR
#      - Publicar métricas no CloudWatch
#      - Operar o CNI (Container Network Interface) da AWS
#
# Conceito-chave — Assume Role Policy (Trust Policy):
#   Toda IAM Role precisa de uma "trust policy" que define QUEM pode
#   assumir aquela role. Para o EKS, quem assume é o serviço eks.amazonaws.com.
#   Para os nodes, quem assume é o serviço ec2.amazonaws.com.
# =============================================================================

# -----------------------------------------------------------------------------
# Role do Control Plane do EKS
# -----------------------------------------------------------------------------

# Trust policy: permite que o serviço EKS assuma esta role
data "aws_iam_policy_document" "cluster_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${var.project}-eks-cluster-role"
  assume_role_policy = data.aws_iam_policy_document.cluster_assume_role.json

  tags = {
    Name        = "${var.project}-eks-cluster-role"
    Environment = var.environment
    Project     = var.project
  }
}

# AmazonEKSClusterPolicy: policy gerenciada pela AWS que concede ao control plane
# as permissões mínimas para operar o cluster (gerenciar ENIs, SGs, ELBs, etc.)
resource "aws_iam_role_policy_attachment" "cluster_policy" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# -----------------------------------------------------------------------------
# Role dos Nodes EC2
# -----------------------------------------------------------------------------

# Trust policy: permite que instâncias EC2 assumam esta role
data "aws_iam_policy_document" "node_assume_role" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "node" {
  name               = "${var.project}-eks-node-role"
  assume_role_policy = data.aws_iam_policy_document.node_assume_role.json

  tags = {
    Name        = "${var.project}-eks-node-role"
    Environment = var.environment
    Project     = var.project
  }
}

# AmazonEKSWorkerNodePolicy: permite ao node registrar-se no cluster,
# descrever instâncias e interagir com a API do EKS.
resource "aws_iam_role_policy_attachment" "node_worker_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

# AmazonEKS_CNI_Policy: necessária para o AWS VPC CNI plugin, que é responsável
# por alocar IPs da VPC diretamente para os pods. Sem esta policy, os pods
# não recebem endereços IP e o cluster não funciona.
resource "aws_iam_role_policy_attachment" "node_cni_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# AmazonEC2ContainerRegistryReadOnly: permite que os nodes façam pull de
# imagens Docker armazenadas no ECR (Elastic Container Registry) da AWS.
# Sem esta policy, pods que usam imagens do ECR falham com ImagePullBackOff.
resource "aws_iam_role_policy_attachment" "node_ecr_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# CloudWatchAgentServerPolicy: permite que os nodes publiquem logs e métricas
# no CloudWatch. Útil para diagnóstico durante os estudos.
resource "aws_iam_role_policy_attachment" "node_cloudwatch_policy" {
  role       = aws_iam_role.node.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}