# =============================================================================
# modules/rds/variables.tf
# Variáveis de entrada do módulo RDS.
#
# Este módulo recebe atributos de rede do módulo VPC e atributos de segurança
# do módulo EKS (via main.tf raiz), além dos parâmetros do banco definidos
# no terraform.tfvars.
# =============================================================================

# -----------------------------------------------------------------------------
# Identificação
# -----------------------------------------------------------------------------

variable "project" {
  description = "Nome do projeto. Usado como prefixo nos nomes dos recursos RDS e nas tags."
  type        = string
}

variable "environment" {
  description = "Nome do ambiente (ex: lab, dev, prod). Usado em tags."
  type        = string
}

# -----------------------------------------------------------------------------
# Rede — recebidos como outputs do módulo VPC
# -----------------------------------------------------------------------------

variable "vpc_id" {
  description = "ID da VPC. Usado para associar o Security Group do RDS à rede correta."
  type        = string
}

variable "private_subnet_id" {
  description = "ID da subnet privada onde o RDS será provisionado. O banco nunca fica em subnet pública."
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block da VPC. Usado como origem permitida nas regras de entrada do Security Group do RDS."
  type        = string
}

# -----------------------------------------------------------------------------
# Segurança — recebido como output do módulo EKS
# -----------------------------------------------------------------------------

variable "node_security_group_id" {
  description = "ID do Security Group dos nodes EKS. Apenas tráfego originado dos nodes será aceito pelo RDS na porta 5432."
  type        = string
}

# -----------------------------------------------------------------------------
# Configuração do banco de dados
# -----------------------------------------------------------------------------

variable "db_instance_class" {
  description = "Classe da instância RDS. Define CPU e memória do banco."
  type        = string
}

variable "db_allocated_storage" {
  description = "Tamanho do disco do RDS em GB."
  type        = number
}

variable "db_name" {
  description = "Nome do banco de dados criado automaticamente na instância RDS."
  type        = string
}

variable "db_username" {
  description = "Usuário master do PostgreSQL."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Senha master do PostgreSQL."
  type        = string
  sensitive   = true
}