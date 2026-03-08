# =============================================================================
# modules/eks/outputs.tf
# Exporta os atributos do cluster EKS para consumo pelo main.tf raiz,
# que os repassa aos módulos addons e ao outputs.tf raiz.
#
# Fluxo:
#   modules/eks/outputs.tf
#       └── terraform/main.tf (module.eks.cluster_name, module.eks.cluster_endpoint ...)
#               ├── module "addons"     (precisa do endpoint e do CA para configurar
#               │                        os providers kubernetes e helm)
#               └── terraform/outputs.tf (expõe endpoint e cluster_name ao usuário)
# =============================================================================

output "cluster_name" {
  description = "Nome do cluster EKS. Usado pelo módulo addons e pelo comando aws eks update-kubeconfig."
  value       = aws_eks_cluster.main.name
}

output "cluster_endpoint" {
  description = "URL do API server do EKS. Usado pelos providers kubernetes e helm para se conectar ao cluster."
  value       = aws_eks_cluster.main.endpoint
}

output "cluster_ca_certificate" {
  description = "Certificado CA do cluster em base64. Usado pelos providers kubernetes e helm para validar o TLS do API server."
  value       = aws_eks_cluster.main.certificate_authority[0].data
}

output "cluster_version" {
  description = "Versão do Kubernetes em execução no cluster. Útil para validar compatibilidade dos addons."
  value       = aws_eks_cluster.main.version
}

output "node_group_role_arn" {
  description = "ARN da IAM Role dos nodes EC2. Usado pelo módulo addons para configurar o aws-auth ConfigMap, que autoriza os nodes a se registrarem no cluster."
  value       = aws_iam_role.node.arn
}

output "node_security_group_id" {
  description = "ID do Security Group criado automaticamente pelo EKS para os nodes. Usado pelo módulo rds para permitir conexão dos nodes ao PostgreSQL na porta 5432."
  value       = aws_eks_cluster.main.vpc_config[0].cluster_security_group_id
}