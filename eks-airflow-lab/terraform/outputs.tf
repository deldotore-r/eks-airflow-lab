# =============================================================================
# terraform/outputs.tf
# Consolida e exibe os valores mais úteis ao final do terraform apply.
#
# Estes outputs servem a dois propósitos:
#   1. Exibição imediata no terminal após o apply — o usuário vê os
#      endpoints e comandos prontos para uso sem precisar abrir o console AWS.
#   2. Referência programática — outros sistemas podem chamar
#      `terraform output -raw <nome>` para obter valores em scripts.
#
# Outputs sensíveis (senhas) são marcados com sensitive = true e não
# aparecem no terminal. Para consultá-los: terraform output -raw <nome>
# =============================================================================

# -----------------------------------------------------------------------------
# Cluster EKS
# -----------------------------------------------------------------------------

output "cluster_name" {
  description = "Nome do cluster EKS."
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "URL do API server do EKS. Usado pelo kubectl para se comunicar com o cluster."
  value       = module.eks.cluster_endpoint
}

output "cluster_version" {
  description = "Versão do Kubernetes em execução no cluster."
  value       = module.eks.cluster_version
}

# Comando pronto para configurar o kubectl local após o apply.
# Basta copiar e colar no terminal.
output "kubeconfig_command" {
  description = "Comando para configurar o kubectl local apontar para este cluster."
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

# -----------------------------------------------------------------------------
# RDS PostgreSQL
# -----------------------------------------------------------------------------

output "db_endpoint" {
  description = "Endpoint de conexão do RDS. Formato: hostname:5432."
  value       = module.rds.db_endpoint
}

output "db_instance_id" {
  description = "Identificador da instância RDS no console AWS."
  value       = module.rds.db_instance_id
}

# -----------------------------------------------------------------------------
# Airflow
# -----------------------------------------------------------------------------

output "airflow_namespace" {
  description = "Namespace Kubernetes onde o Airflow foi instalado."
  value       = module.addons.airflow_namespace
}

# Comando pronto para obter o endereço do ALB do Airflow após o apply.
output "airflow_ui_command" {
  description = "Comando para obter o endereço da UI do Airflow (aguardar ~2 minutos após o apply para o ALB ficar ativo)."
  value       = "kubectl get ingress -n ${module.addons.airflow_namespace} -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}'"
}

# -----------------------------------------------------------------------------
# Status dos Helm releases
# Útil para validar rapidamente se todos os componentes foram instalados.
# Valor esperado para todos: "deployed"
# -----------------------------------------------------------------------------

output "helm_status" {
  description = "Status dos Helm releases instalados no cluster. Todos devem estar como 'deployed'."
  value = {
    airflow            = module.addons.airflow_helm_status
    lb_controller      = module.addons.lb_controller_helm_status
    cluster_autoscaler = module.addons.cluster_autoscaler_helm_status
    metrics_server     = module.addons.metrics_server_helm_status
  }
}

# -----------------------------------------------------------------------------
# Outputs sensíveis — não exibidos no terminal, mas consultáveis via CLI
# terraform output -raw db_username
# terraform output -raw db_password
# terraform output -raw airflow_webserver_password
# -----------------------------------------------------------------------------

output "db_username" {
  description = "Usuário master do RDS. Consultar com: terraform output -raw db_username"
  value       = var.db_username
  sensitive   = true
}

output "db_password" {
  description = "Senha master do RDS. Consultar com: terraform output -raw db_password"
  value       = var.db_password
  sensitive   = true
}

output "airflow_webserver_password" {
  description = "Senha do admin da UI do Airflow. Consultar com: terraform output -raw airflow_webserver_password"
  value       = var.airflow_webserver_password
  sensitive   = true
}