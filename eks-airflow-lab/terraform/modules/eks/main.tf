# =============================================================================
# modules/eks/main.tf
# Cria o cluster EKS gerenciado e o node group de instâncias EC2.
#
# Recursos criados:
#   - aws_eks_cluster      : control plane gerenciado pela AWS
#   - aws_eks_node_group   : grupo de nodes EC2 que executam os pods
#   - aws_security_group   : regras de rede para o control plane
#   - aws_launch_template  : configuração base das instâncias EC2 dos nodes
# =============================================================================

# -----------------------------------------------------------------------------
# Security Group do Control Plane
# Controla o tráfego de entrada e saída da API do EKS.
# -----------------------------------------------------------------------------

resource "aws_security_group" "cluster" {
  name        = "${var.project}-eks-cluster-sg"
  description = "Security group do control plane EKS. Controla acesso à API do cluster."
  vpc_id      = var.vpc_id

  # Permite todo tráfego de saída do control plane.
  # Necessário para que o control plane se comunique com os nodes e com
  # serviços AWS (ECR, CloudWatch, S3, etc.).
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"          # -1 significa todos os protocolos
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-eks-cluster-sg"
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# Cluster EKS — control plane gerenciado pela AWS
# A AWS provisiona e gerencia: etcd, API server, controller manager, scheduler.
# Você paga $0,10/hora pelo control plane independentemente do número de nodes.
# -----------------------------------------------------------------------------

resource "aws_eks_cluster" "main" {
  name     = var.cluster_name
  version  = var.kubernetes_version

  # ARN da role IAM que o control plane usará para chamar APIs da AWS.
  # Definida em iam.tf deste mesmo módulo.
  role_arn = aws_iam_role.cluster.arn

  vpc_config {
    # Subnet onde o control plane criará ENIs para se comunicar com os nodes.
    subnet_ids = [var.private_subnet_id]

    # IDs dos security groups associados ao control plane.
    security_group_ids = [aws_security_group.cluster.id]

    # true  = API server acessível pela internet (via endpoint público da AWS)
    # Necessário para que o kubectl local (sua máquina Fedora) acesse o cluster.
    endpoint_public_access = true

    # true = API server também acessível de dentro da VPC.
    # Necessário para que os nodes se comuniquem com o control plane internamente.
    endpoint_private_access = true
  }

  # Logs do control plane enviados ao CloudWatch.
  # Útil para diagnóstico durante estudos. Cada tipo tem custo de ingestão.
  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  # O cluster só pode ser criado após a role IAM ter as policies anexadas.
  # Sem depends_on, o Terraform pode tentar criar o cluster antes das policies
  # estarem prontas, resultando em erro de permissão.
  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy
  ]

  tags = {
    Name        = var.cluster_name
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# Launch Template — configuração base das instâncias EC2 dos nodes
# Permite customizar as instâncias além do que o node group expõe diretamente.
# -----------------------------------------------------------------------------

resource "aws_launch_template" "node" {
  name_prefix   = "${var.project}-node-"
  instance_type = var.node_instance_type

  # Metadados da instância: configuração do serviço IMDSv2.
  # IMDSv2 é obrigatório para clusters EKS modernos por questões de segurança.
  # Impede que pods maliciosos acessem credenciais da instância via SSRF.
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"  # Força IMDSv2 (token obrigatório)
    http_put_response_hop_limit = 2           # Permite que pods acessem o metadata (hop extra)
  }

  # Habilita monitoramento detalhado do EC2 (métricas a cada 1 minuto).
  # O padrão é básico (5 minutos). Tem custo adicional mínimo.
  monitoring {
    enabled = true
  }

  tag_specifications {
    resource_type = "instance"

    tags = {
      Name        = "${var.project}-eks-node"
      Environment = var.environment
      Project     = var.project
    }
  }

  tags = {
    Name        = "${var.project}-node-lt"
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# Node Group — grupo de instâncias EC2 que executam os pods
# O EKS gerencia o ciclo de vida das instâncias (criação, atualização, drenagem).
# -----------------------------------------------------------------------------

resource "aws_eks_node_group" "main" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "${var.project}-node-group"

  # ARN da role IAM que cada node usará. Definida em iam.tf.
  node_role_arn = aws_iam_role.node.arn

  # Subnet onde os nodes EC2 serão lançados.
  # Nodes ficam na subnet privada — sem IP público, sem exposição direta.
  subnet_ids = [var.private_subnet_id]

  # Parâmetros de escalonamento do node group.
  # O Cluster Autoscaler ajusta o desired_size entre min e max conforme a demanda.
  scaling_config {
    desired_size = var.node_desired_size
    min_size     = var.node_min_size
    max_size     = var.node_max_size
  }

  # Referencia o launch template definido acima.
  # version = "$Latest" sempre usa a versão mais recente do template.
  launch_template {
    id      = aws_launch_template.node.id
    version = "$Latest"
  }

  # Estratégia de atualização dos nodes.
  # max_unavailable = 1: durante um rolling update, no máximo 1 node fica
  # indisponível por vez. Garante que o cluster nunca fique sem capacidade.
  update_config {
    max_unavailable = 1
  }

  # O node group só pode ser criado após todas as policies IAM dos nodes
  # estarem anexadas. Caso contrário, os nodes não conseguem se registrar.
  depends_on = [
    aws_iam_role_policy_attachment.node_worker_policy,
    aws_iam_role_policy_attachment.node_cni_policy,
    aws_iam_role_policy_attachment.node_ecr_policy,
    aws_iam_role_policy_attachment.node_cloudwatch_policy,
  ]

  tags = {
    Name        = "${var.project}-node-group"
    Environment = var.environment
    Project     = var.project

    # Tag obrigatória para o Cluster Autoscaler identificar e gerenciar
    # este node group. O valor deve ser "owned" ou "shared".
    "k8s.io/cluster-autoscaler/${var.cluster_name}" = "owned"
    "k8s.io/cluster-autoscaler/enabled"             = "true"
  }
}

