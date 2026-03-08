# =============================================================================
# modules/addons/variables.tf
# Variáveis de entrada do módulo addons.
#
# Este é o módulo que mais recebe inputs de outros módulos: ele precisa de
# atributos do EKS (para configurar os providers kubernetes e helm),
# do RDS (para montar a connection string do Airflow) e de identificação
# geral do projeto.
#
# Dependências de outros módulos:
#   - módulo eks : cluster_name, cluster_endpoint, cluster_ca_certificate
#   - módulo rds : db_host, db_port, db_name
#   - raiz       : db_username, db_password, airflow_webserver_password
# =============================================================================

# -----------------------------------------------------------------------------
# Identificação
# -----------------------------------------------------------------------------

variable "project" {
  description = "Nome do projeto. Usado como prefixo em nomes de recursos e tags."
  type        = string
}

variable "environment" {
  description = "Nome do ambiente (ex: lab, dev, prod). Usado em tags."
  type        = string
}

variable "aws_region" {
  description = "Região AWS. Necessária para configurar o Cluster Autoscaler com a região correta."
  type        = string
}

# -----------------------------------------------------------------------------
# EKS — recebidos como outputs do módulo eks
# Necessários para que os providers kubernetes e helm consigam
# autenticar e se conectar ao cluster após sua criação.
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Nome do cluster EKS. Usado pelo Cluster Autoscaler para identificar o cluster que deve gerenciar."
  type        = string
}

variable "cluster_endpoint" {
  description = "URL do API server do EKS. Usado pelos providers kubernetes e helm para estabelecer conexão com o cluster."
  type        = string
}

variable "cluster_ca_certificate" {
  description = "Certificado CA do cluster em base64. Usado pelos providers kubernetes e helm para validar o TLS do API server."
  type        = string
}

# -----------------------------------------------------------------------------
# RDS — recebidos como outputs do módulo rds
# Usados para montar a connection string do Airflow.
# -----------------------------------------------------------------------------

variable "db_host" {
  description = "Hostname do RDS PostgreSQL. Componente do SQLAlchemy connection string do Airflow."
  type        = string
}

variable "db_port" {
  description = "Porta do PostgreSQL (5432). Componente do SQLAlchemy connection string do Airflow."
  type        = number
}

variable "db_name" {
  description = "Nome do banco de dados PostgreSQL. Componente do SQLAlchemy connection string do Airflow."
  type        = string
}

# -----------------------------------------------------------------------------
# Credenciais — recebidas diretamente do terraform.tfvars via main.tf raiz
# Não passam pelo módulo RDS para minimizar a superfície de exposição.
# -----------------------------------------------------------------------------

variable "db_username" {
  description = "Usuário master do PostgreSQL. Usado na connection string do Airflow."
  type        = string
  sensitive   = true
}

variable "db_password" {
  description = "Senha master do PostgreSQL. Usada na connection string do Airflow."
  type        = string
  sensitive   = true
}

variable "airflow_webserver_password" {
  description = "Senha do usuário admin da UI do Airflow."
  type        = string
  sensitive   = true
}

# -----------------------------------------------------------------------------
# Airflow — parâmetros do Helm chart
# -----------------------------------------------------------------------------

variable "airflow_namespace" {
  description = "Namespace Kubernetes onde o Airflow será instalado."
  type        = string
}

variable "airflow_chart_version" {
  description = "Versão do Helm chart oficial do Apache Airflow. Fixar versão evita upgrades acidentais."
  type        = string
}