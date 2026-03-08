# =============================================================================
# modules/addons/main.tf
# Instala todos os componentes dentro do cluster EKS via Helm.
#
# Ordem de instalação (dependências explícitas via depends_on):
#   1. Namespace airflow
#   2. Metrics Server          (independente, sem dependências)
#   3. AWS Load Balancer Controller (precisa do cluster ativo)
#   4. Cluster Autoscaler      (precisa do cluster ativo)
#   5. Apache Airflow          (precisa do namespace, do RDS e do LB Controller)
#
# Providers kubernetes e helm são configurados localmente neste módulo
# usando os outputs do módulo EKS recebidos como variáveis.
# =============================================================================

# -----------------------------------------------------------------------------
# Configuração dos providers kubernetes e helm
# Estes providers precisam das credenciais do cluster para operar.
# Como são configurados dentro do módulo (não no bloco raiz), usamos
# a sintaxe de "provider aliases" implícitos via required_providers no main
# raiz — o Terraform passa a configuração automaticamente.
# -----------------------------------------------------------------------------

# Data source: obtém o token de autenticação temporário para o cluster EKS.
# O token é gerado pela AWS e tem validade curta (~15 minutos).
# É equivalente ao que `aws eks get-token` retorna no CLI.
data "aws_eks_cluster_auth" "main" {
  name = var.cluster_name
}

# -----------------------------------------------------------------------------
# Namespace do Airflow
# Criado antes do Helm release para garantir que existe antes da instalação.
# -----------------------------------------------------------------------------

resource "kubernetes_namespace" "airflow" {
  metadata {
    name = var.airflow_namespace

    labels = {
      name        = var.airflow_namespace
      environment = var.environment
      project     = var.project
    }
  }
}

# -----------------------------------------------------------------------------
# Metrics Server
# Coleta métricas de CPU e memória de todos os pods e nodes.
# Necessário para: kubectl top nodes/pods, HPA (Horizontal Pod Autoscaler)
# e o Kubernetes Dashboard.
# -----------------------------------------------------------------------------

resource "helm_release" "metrics_server" {
  name       = "metrics-server"
  repository = "https://kubernetes-sigs.github.io/metrics-server/"
  chart      = "metrics-server"
  namespace  = "kube-system"  # Instalado no namespace de sistema do Kubernetes
  version    = "3.12.1"

  # Necessário em alguns clusters EKS onde o kubelet usa certificado
  # auto-assinado. Sem isso, o Metrics Server rejeita a conexão com os nodes.
  set {
    name  = "args[0]"
    value = "--kubelet-insecure-tls"
  }

  timeout = 300  # 5 minutos — tempo máximo para o chart ser instalado

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# AWS Load Balancer Controller
# Observa recursos Ingress e Service do tipo LoadBalancer no cluster e
# cria/gerencia ALBs e NLBs automaticamente na AWS.
# Sem este controller, os Ingress ficam em estado "pending" indefinidamente.
# -----------------------------------------------------------------------------

# IAM Policy que permite ao controller criar e gerenciar load balancers na AWS.
# O JSON da policy é o documento oficial da AWS para o LB Controller.
data "aws_iam_policy_document" "lb_controller" {
  statement {
    effect = "Allow"
    actions = [
      "iam:CreateServiceLinkedRole",
      "ec2:DescribeAccountAttributes",
      "ec2:DescribeAddresses",
      "ec2:DescribeAvailabilityZones",
      "ec2:DescribeInternetGateways",
      "ec2:DescribeVpcs",
      "ec2:DescribeSubnets",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeInstances",
      "ec2:DescribeNetworkInterfaces",
      "ec2:DescribeTags",
      "ec2:GetCoipPoolUsage",
      "ec2:DescribeCoipPools",
      "elasticloadbalancing:DescribeLoadBalancers",
      "elasticloadbalancing:DescribeLoadBalancerAttributes",
      "elasticloadbalancing:DescribeListeners",
      "elasticloadbalancing:DescribeListenerCertificates",
      "elasticloadbalancing:DescribeSSLPolicies",
      "elasticloadbalancing:DescribeRules",
      "elasticloadbalancing:DescribeTargetGroups",
      "elasticloadbalancing:DescribeTargetGroupAttributes",
      "elasticloadbalancing:DescribeTargetHealth",
      "elasticloadbalancing:DescribeTags",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "elasticloadbalancing:CreateLoadBalancer",
      "elasticloadbalancing:CreateListener",
      "elasticloadbalancing:CreateRule",
      "elasticloadbalancing:CreateTargetGroup",
      "elasticloadbalancing:DeleteLoadBalancer",
      "elasticloadbalancing:DeleteListener",
      "elasticloadbalancing:DeleteRule",
      "elasticloadbalancing:DeleteTargetGroup",
      "elasticloadbalancing:ModifyLoadBalancerAttributes",
      "elasticloadbalancing:ModifyListener",
      "elasticloadbalancing:ModifyRule",
      "elasticloadbalancing:ModifyTargetGroup",
      "elasticloadbalancing:ModifyTargetGroupAttributes",
      "elasticloadbalancing:RegisterTargets",
      "elasticloadbalancing:DeregisterTargets",
      "elasticloadbalancing:SetIpAddressType",
      "elasticloadbalancing:SetSecurityGroups",
      "elasticloadbalancing:SetSubnets",
      "elasticloadbalancing:AddTags",
      "elasticloadbalancing:RemoveTags",
      "ec2:AuthorizeSecurityGroupIngress",
      "ec2:RevokeSecurityGroupIngress",
      "ec2:CreateSecurityGroup",
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ec2:DeleteSecurityGroup",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lb_controller" {
  name        = "${var.project}-lb-controller-policy"
  description = "Permite ao AWS Load Balancer Controller gerenciar ALBs e NLBs."
  policy      = data.aws_iam_policy_document.lb_controller.json
}

# IRSA (IAM Roles for Service Accounts):
# Permite que um ServiceAccount Kubernetes assuma uma IAM Role AWS.
# É o mecanismo correto para dar permissões AWS a pods — sem precisar
# de credenciais hardcoded ou de dar permissões extras aos nodes EC2.
data "aws_caller_identity" "current" {}

data "aws_iam_openid_connect_provider" "eks" {
  # O EKS expõe um OIDC provider que o Terraform usa para criar a trust policy.
  # A URL é derivada do cluster_name via data source.
  url = "https://oidc.eks.${var.aws_region}.amazonaws.com/id/${var.cluster_name}"
}

data "aws_iam_policy_document" "lb_controller_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:aws-load-balancer-controller"]
    }
  }
}

resource "aws_iam_role" "lb_controller" {
  name               = "${var.project}-lb-controller-role"
  assume_role_policy = data.aws_iam_policy_document.lb_controller_assume.json
}

resource "aws_iam_role_policy_attachment" "lb_controller" {
  role       = aws_iam_role.lb_controller.name
  policy_arn = aws_iam_policy.lb_controller.arn
}

resource "helm_release" "lb_controller" {
  name       = "aws-load-balancer-controller"
  repository = "https://aws.github.io/eks-charts"
  chart      = "aws-load-balancer-controller"
  namespace  = "kube-system"
  version    = "1.7.2"

  set {
    name  = "clusterName"
    value = var.cluster_name
  }

  # ARN da role IRSA criada acima — o controller usará essa role para
  # criar ALBs na AWS sem precisar de credenciais explícitas.
  set {
    name  = "serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.lb_controller.arn
  }

  set {
    name  = "region"
    value = var.aws_region
  }

  depends_on = [aws_iam_role_policy_attachment.lb_controller]

  timeout = 300

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# Cluster Autoscaler
# Monitora pods em estado "Pending" (sem node disponível) e escala o
# node group adicionando instâncias EC2. Remove nodes ociosos após cooldown.
# -----------------------------------------------------------------------------

data "aws_iam_policy_document" "autoscaler" {
  statement {
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeAutoScalingInstances",
      "autoscaling:DescribeLaunchConfigurations",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeTags",
      "ec2:DescribeInstanceTypes",
      "ec2:DescribeLaunchTemplateVersions",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "autoscaling:SetDesiredCapacity",
      "autoscaling:TerminateInstanceInAutoScalingGroup",
    ]
    # Restringe as ações de escalonamento apenas ao Auto Scaling Group
    # do node group deste cluster — princípio do menor privilégio.
    resources = ["*"]

    condition {
      test     = "StringEquals"
      variable = "autoscaling:ResourceTag/k8s.io/cluster-autoscaler/${var.cluster_name}"
      values   = ["owned"]
    }
  }
}

resource "aws_iam_policy" "autoscaler" {
  name        = "${var.project}-cluster-autoscaler-policy"
  description = "Permite ao Cluster Autoscaler escalar o node group do EKS."
  policy      = data.aws_iam_policy_document.autoscaler.json
}

data "aws_iam_policy_document" "autoscaler_assume" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${replace(data.aws_iam_openid_connect_provider.eks.url, "https://", "")}:sub"
      values   = ["system:serviceaccount:kube-system:cluster-autoscaler"]
    }
  }
}

resource "aws_iam_role" "autoscaler" {
  name               = "${var.project}-cluster-autoscaler-role"
  assume_role_policy = data.aws_iam_policy_document.autoscaler_assume.json
}

resource "aws_iam_role_policy_attachment" "autoscaler" {
  role       = aws_iam_role.autoscaler.name
  policy_arn = aws_iam_policy.autoscaler.arn
}

resource "helm_release" "cluster_autoscaler" {
  name       = "cluster-autoscaler"
  repository = "https://kubernetes.github.io/autoscaler"
  chart      = "cluster-autoscaler"
  namespace  = "kube-system"
  version    = "9.36.0"

  set {
    name  = "autoDiscovery.clusterName"
    value = var.cluster_name
  }

  set {
    name  = "awsRegion"
    value = var.aws_region
  }

  set {
    name  = "rbac.serviceAccount.annotations.eks\\.amazonaws\\.com/role-arn"
    value = aws_iam_role.autoscaler.arn
  }

  # Evita que o autoscaler remova nodes que contêm pods do sistema (kube-system).
  set {
    name  = "extraArgs.skip-nodes-with-system-pods"
    value = "false"
  }

  depends_on = [aws_iam_role_policy_attachment.autoscaler]

  timeout = 300

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# Apache Airflow
# Instalado via Helm chart oficial. Usa KubernetesExecutor: cada task
# da DAG é executada como um pod isolado no cluster.
# -----------------------------------------------------------------------------

resource "helm_release" "airflow" {
  name       = "airflow"
  repository = "https://airflow.apache.org"
  chart      = "airflow"
  namespace  = kubernetes_namespace.airflow.metadata[0].name
  version    = var.airflow_chart_version

  # Executor: KubernetesExecutor cria um pod por task.
  # Alternativas: LocalExecutor (subprocesso), CeleryExecutor (workers fixos).
  set {
    name  = "executor"
    value = "KubernetesExecutor"
  }

  # Connection string SQLAlchemy para o RDS PostgreSQL.
  # Formato: postgresql+psycopg2://user:password@host:port/dbname
  set {
    name  = "data.metadataConnection.user"
    value = var.db_username
  }

  set {
    name  = "data.metadataConnection.pass"
    value = var.db_password
  }

  set {
    name  = "data.metadataConnection.host"
    value = var.db_host
  }

  set {
    name  = "data.metadataConnection.port"
    value = var.db_port
  }

  set {
    name  = "data.metadataConnection.db"
    value = var.db_name
  }

  set {
    name  = "data.metadataConnection.protocol"
    value = "postgresql"
  }

  # Credenciais do usuário admin da UI do Airflow.
  set {
    name  = "webserver.defaultUser.enabled"
    value = "true"
  }

  set {
    name  = "webserver.defaultUser.username"
    value = "admin"
  }

  set {
    name  = "webserver.defaultUser.password"
    value = var.airflow_webserver_password
  }

  set {
    name  = "webserver.defaultUser.role"
    value = "Admin"
  }

  # Ingress: expõe o webserver via ALB criado pelo Load Balancer Controller.
  set {
    name  = "ingress.web.enabled"
    value = "true"
  }

  set {
    name  = "ingress.web.annotations.kubernetes\\.io/ingress\\.class"
    value = "alb"
  }

  set {
    name  = "ingress.web.annotations.alb\\.ingress\\.kubernetes\\.io/scheme"
    value = "internet-facing"
  }

  set {
    name  = "ingress.web.annotations.alb\\.ingress\\.kubernetes\\.io/target-type"
    value = "ip"
  }

  # Desabilita o banco PostgreSQL embutido do chart — usamos o RDS externo.
  set {
    name  = "postgresql.enabled"
    value = "false"
  }

  # Desabilita o Redis embutido — não necessário para KubernetesExecutor.
  # Redis só é necessário para CeleryExecutor.
  set {
    name  = "redis.enabled"
    value = "false"
  }

  # Garante que o Airflow só seja instalado após o namespace existir,
  # o LB Controller estar pronto para processar o Ingress,
  # e o Metrics Server estar disponível.
  depends_on = [
    kubernetes_namespace.airflow,
    helm_release.lb_controller,
    helm_release.metrics_server,
  ]

  timeout = 600  # 10 minutos — o Airflow demora mais para inicializar

  tags = {
    Environment = var.environment
    Project     = var.project
  }
}