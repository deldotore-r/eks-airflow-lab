# =============================================================================
# modules/eks/variables.tf
# Variáveis de entrada do módulo EKS.
#
# Este módulo recebe atributos de rede do módulo VPC (via main.tf raiz)
# e parâmetros de configuração do cluster definidos no terraform.tfvars.
# =============================================================================

# -----------------------------------------------------------------------------
# Identificação
# -----------------------------------------------------------------------------

variable "project" {
  description = "Nome do projeto. Usado como prefixo nos nomes dos recursos EKS e nas tags."
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
  description = "ID da VPC onde o cluster EKS será criado. Recebido do output do módulo vpc."
  type        = string
}

variable "private_subnet_id" {
  description = "ID da subnet privada onde os nodes EC2 do cluster serão lançados."
  type        = string
}

# -----------------------------------------------------------------------------
# Cluster EKS
# -----------------------------------------------------------------------------

variable "cluster_name" {
  description = "Nome do cluster EKS. Usado também pelo kubectl e pelo aws eks update-kubeconfig."
  type        = string
}

variable "kubernetes_version" {
  description = "Versão do Kubernetes a ser usada no cluster EKS."
  type        = string
}

# -----------------------------------------------------------------------------
# Node Group
# -----------------------------------------------------------------------------

variable "node_instance_type" {
  description = "Tipo de instância EC2 dos nodes. Define CPU e memória disponíveis para os pods."
  type        = string
}

variable "node_desired_size" {
  description = "Número inicial de nodes ao criar o cluster. O Cluster Autoscaler ajusta a partir deste valor."
  type        = number
}

variable "node_min_size" {
  description = "Número mínimo de nodes. O Cluster Autoscaler nunca desce abaixo deste valor."
  type        = number
}

variable "node_max_size" {
  description = "Número máximo de nodes. O Cluster Autoscaler nunca ultrapassa este valor ao escalar."
  type        = number
}