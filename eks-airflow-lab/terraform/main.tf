# =============================================================================
# terraform/main.tf
# Orquestrador raiz do projeto. Não cria recursos diretamente — instancia
# os módulos e costura suas dependências passando outputs de um como
# inputs de outro.
#
# Ordem de criação (inferida pelo Terraform via dependências):
#   1. module.vpc      (sem dependências externas)
#   2. module.eks      (depende de outputs do vpc)
#   3. module.rds      (depende de outputs do vpc e do eks)
#   4. module.addons   (depende de outputs do eks e do rds)
#
# Providers kubernetes e helm são configurados aqui no escopo raiz
# e repassados implicitamente aos módulos que os utilizam.
# =============================================================================

# -----------------------------------------------------------------------------
# Configuração do provider AWS
# -----------------------------------------------------------------------------

provider "aws" {
  region = var.aws_region

  # Tags padrão aplicadas automaticamente a todos os recursos AWS criados
  # por este projeto. Útil para identificação no console e billing.
  default_tags {
    tags = {
      Project     = var.project
      Environment = var.environment
      ManagedBy   = "terraform"
    }
  }
}

# -----------------------------------------------------------------------------
# Configuração dos providers kubernetes e helm
# Ambos precisam das credenciais do cluster EKS para operar.
# Como o cluster ainda não existe no momento do terraform init, usamos
# data sources que são resolvidos apenas durante o apply, após o cluster
# estar disponível.
# -----------------------------------------------------------------------------

# Obtém o token de autenticação temporário para o cluster EKS.
# Resolvido durante o apply, após o module.eks ser criado.
data "aws_eks_cluster_auth" "main" {
  name = module.eks.cluster_name
}

provider "kubernetes" {
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
  token                  = data.aws_eks_cluster_auth.main.token
}

provider "helm" {
  kubernetes {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_ca_certificate)
    token                  = data.aws_eks_cluster_auth.main.token
  }
}

# -----------------------------------------------------------------------------
# Módulo VPC
# Cria toda a infraestrutura de rede: VPC, subnets, IGW, NAT Gateway,
# route tables. Não depende de nenhum outro módulo.
# -----------------------------------------------------------------------------

module "vpc" {
  source = "./modules/vpc"

  # Identificação
  project     = var.project
  environment = var.environment

  # Rede
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = var.availability_zone
}

# -----------------------------------------------------------------------------
# Módulo EKS
# Cria o cluster Kubernetes e o node group EC2.
# Depende do módulo VPC para receber IDs de rede.
# -----------------------------------------------------------------------------

module "eks" {
  source = "./modules/eks"

  # Identificação
  project     = var.project
  environment = var.environment

  # Rede — recebidos dos outputs do módulo vpc
  vpc_id            = module.vpc.vpc_id
  private_subnet_id = module.vpc.private_subnet_id

  # Cluster
  cluster_name       = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Node group
  node_instance_type = var.node_instance_type
  node_desired_size  = var.node_desired_size
  node_min_size      = var.node_min_size
  node_max_size      = var.node_max_size
}

# -----------------------------------------------------------------------------
# Módulo RDS
# Cria o banco PostgreSQL para metadados do Airflow.
# Depende do módulo VPC (rede) e do módulo EKS (security group dos nodes).
# -----------------------------------------------------------------------------

module "rds" {
  source = "./modules/rds"

  # Identificação
  project     = var.project
  environment = var.environment

  # Rede — recebidos dos outputs do módulo vpc
  vpc_id            = module.vpc.vpc_id
  private_subnet_id = module.vpc.private_subnet_id
  vpc_cidr          = module.vpc.vpc_cidr

  # Segurança — recebido do output do módulo eks
  # Apenas os nodes EKS poderão conectar ao banco na porta 5432
  node_security_group_id = module.eks.node_security_group_id

  # Banco de dados
  db_instance_class    = var.db_instance_class
  db_allocated_storage = var.db_allocated_storage
  db_name              = var.db_name

  # Credenciais sensíveis — vêm diretamente do terraform.tfvars
  db_username = var.db_username
  db_password = var.db_password
}

# -----------------------------------------------------------------------------
# Módulo Addons
# Instala Airflow, LB Controller, Cluster Autoscaler e Metrics Server via Helm.
# Depende do módulo EKS (credenciais do cluster) e do módulo RDS (connection string).
# -----------------------------------------------------------------------------

module "addons" {
  source = "./modules/addons"

  # Identificação
  project     = var.project
  environment = var.environment
  aws_region  = var.aws_region

  # EKS — recebidos dos outputs do módulo eks
  # Usados para configurar os providers kubernetes e helm dentro do módulo
  cluster_name           = module.eks.cluster_name
  cluster_endpoint       = module.eks.cluster_endpoint
  cluster_ca_certificate = module.eks.cluster_ca_certificate

  # RDS — recebidos dos outputs do módulo rds
  # Usados para montar a connection string do Airflow
  db_host = module.rds.db_host
  db_port = module.rds.db_port
  db_name = module.rds.db_name

  # Credenciais sensíveis — vêm diretamente do terraform.tfvars
  # Não passam pelo módulo rds para minimizar superfície de exposição
  db_username = var.db_username
  db_password = var.db_password

  # Airflow
  airflow_namespace          = var.airflow_namespace
  airflow_chart_version      = var.airflow_chart_version
  airflow_webserver_password = var.airflow_webserver_password
}