# =============================================================================
# variables.tf (raiz)
# Declara todas as variáveis de entrada do projeto.
# Valores concretos são fornecidos via terraform.tfvars (não versionar segredos).
#
# Convenção adotada:
#   - Toda variável tem description, type e default quando aplicável.
#   - Variáveis sensíveis (senhas) NÃO têm default — o Terraform exigirá
#     que sejam fornecidas explicitamente, evitando credenciais hardcoded.
# =============================================================================

# -----------------------------------------------------------------------------
# Geral
# -----------------------------------------------------------------------------

variable "project" {
  description = "Nome curto do projeto. Usado como prefixo em todos os recursos AWS para facilitar identificação e billing."
  type        = string
  default     = "eks-airflow-lab"
}

variable "aws_region" {
  description = "Região AWS onde todos os recursos serão provisionados."
  type        = string
  default     = "us-east-1"
}

variable "environment" {
  description = "Nome do ambiente. Usado em tags e nomes de recursos. Ex: lab, dev, prod."
  type        = string
  default     = "lab"
}

# -----------------------------------------------------------------------------
# Rede (VPC)
# -----------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC principal. /16 oferece até 65.536 endereços IP — mais que suficiente para o lab."
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR da subnet pública. Usada pelo ALB, que precisa de acesso externo à internet."
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR da subnet privada. Usada pelos nodes EKS e pelo RDS — sem acesso direto da internet."
  type        = string
  default     = "10.0.2.0/24"
}

variable "availability_zone" {
  description = "AZ onde as subnets serão criadas. Single-AZ para minimizar custo no lab."
  type        = string
  default     = "us-east-1a"
}

# -----------------------------------------------------------------------------
# EKS
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Nome do cluster EKS. Usado também para configurar o kubeconfig local via aws eks update-kubeconfig."
  type        = string
  default     = "eks-airflow-lab"
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes. Deve ser uma versão suportada pelo EKS. Verifique: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html"
  type        = string
  default     = "1.29"
}

variable "node_instance_type" {
  description = "Tipo de instância EC2 dos nodes. t3.medium (2 vCPU, 4GB RAM) é o mínimo viável para rodar Airflow + pods ETL simultaneamente."
  type        = string
  default     = "t3.medium"
}

variable "node_desired_size" {
  description = "Número desejado de nodes no node group. O Cluster Autoscaler pode ajustar entre min e max."
  type        = number
  default     = 2
}

variable "node_min_size" {
  description = "Número mínimo de nodes. Nunca desce abaixo disso, mesmo com cluster ocioso."
  type        = number
  default     = 1
}

variable "node_max_size" {
  description = "Número máximo de nodes. O Cluster Autoscaler não ultrapassa este limite ao escalar."
  type        = number
  default     = 4
}

# -----------------------------------------------------------------------------
# RDS (PostgreSQL — backend de metadados do Airflow)
# -----------------------------------------------------------------------------

variable "db_instance_class" {
  description = "Classe da instância RDS. db.t3.micro é suficiente para os metadados do Airflow em ambiente de lab."
  type        = string
  default     = "db.t3.micro"
}

variable "db_allocated_storage" {
  description = "Tamanho do disco do RDS em GB."
  type        = number
  default     = 20
}

variable "db_name" {
  description = "Nome do banco de dados PostgreSQL criado automaticamente na instância RDS."
  type        = string
  default     = "airflow"
}

variable "db_username" {
  description = "Usuário master do RDS. Não tem default para forçar definição explícita no tfvars."
  type        = string
  sensitive   = true # Marca como sensível: Terraform não exibe este valor em logs ou outputs
}

variable "db_password" {
  description = "Senha master do RDS. Mínimo 8 caracteres. Não tem default — deve ser definida no tfvars e nunca versionada."
  type        = string
  sensitive   = true # Nunca aparece em terraform plan/apply output
}

# -----------------------------------------------------------------------------
# Airflow (Helm chart)
# -----------------------------------------------------------------------------

variable "airflow_namespace" {
  description = "Namespace Kubernetes onde o Airflow será instalado via Helm."
  type        = string
  default     = "airflow"
}

variable "airflow_chart_version" {
  description = "Versão do Helm chart oficial do Apache Airflow. Fixar versão evita upgrades acidentais."
  type        = string
  default     = "1.13.1"
}

variable "airflow_webserver_password" {
  description = "Senha do usuário admin da UI do Airflow. Não tem default — deve ser definida no tfvars."
  type        = string
  sensitive   = true
}