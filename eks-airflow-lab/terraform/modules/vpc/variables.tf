# =============================================================================
# modules/vpc/variables.tf
# Variáveis de entrada do módulo VPC.
#
# Estas variáveis são alimentadas pelo main.tf raiz, que passa os valores
# definidos no terraform.tfvars. O módulo não lê terraform.tfvars diretamente
# — ele só enxerga o que o módulo pai explicitamente passar.
# =============================================================================

variable "project" {
  description = "Nome do projeto. Usado como prefixo nos nomes dos recursos (ex: eks-airflow-lab-vpc)."
  type        = string
}

variable "environment" {
  description = "Nome do ambiente (ex: lab, dev, prod). Usado em tags para identificação no console AWS."
  type        = string
}

variable "vpc_cidr" {
  description = "Bloco CIDR da VPC. Define o espaço de endereçamento IP de toda a rede do projeto."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR da subnet pública. Deve estar contido no vpc_cidr. Usada pelo ALB."
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR da subnet privada. Deve estar contido no vpc_cidr. Usada pelos nodes EKS e RDS."
  type        = string
}

variable "availability_zone" {
  description = "AZ onde as subnets serão criadas. Ambas (pública e privada) ficam na mesma AZ no lab (Single-AZ)."
  type        = string
}