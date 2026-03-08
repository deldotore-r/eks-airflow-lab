# =============================================================================
# versions.tf
# Define a versão mínima do Terraform e pina os providers utilizados.
# Fixar versões é essencial em labs: garante que um terraform init feito
# hoje produza o mesmo resultado daqui a meses, sem surpresas de breaking change.
# =============================================================================

terraform {
  # Versão mínima do Terraform aceita por este projeto.
  # O operador ~> permite patches (1.7.x) mas bloqueia minor incompatíveis (1.8+).
  required_version = "~> 1.7"

  required_providers {

    # Provider AWS: provisiona todos os recursos de infraestrutura (VPC, EKS, RDS, etc.)
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.40"
    }

    # Provider Kubernetes: aplica manifests no cluster após o EKS ser criado.
    # Usado principalmente pelo módulo addons para configurar o cluster.
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.27"
    }

    # Provider Helm: instala charts (Airflow, LB Controller, Autoscaler, Metrics Server)
    # diretamente via Terraform, sem precisar de comandos helm manuais.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.13"
    }

    # Provider TLS: gera o par de chaves RSA usado para acesso SSH aos nodes EC2.
    # A chave privada fica no state do Terraform — aceitável para lab, não para prod.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }

    # Provider Random: gera sufixos aleatórios para nomes de recursos que exigem
    # unicidade global na AWS (ex: nome do bucket S3, identificador do RDS).
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}