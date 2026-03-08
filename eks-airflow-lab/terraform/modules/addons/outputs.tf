# =============================================================================
# modules/addons/outputs.tf
# Exporta atributos dos componentes instalados via Helm para consumo
# pelo outputs.tf raiz, que os exibe ao usuário após o terraform apply.
#
# Fluxo:
#   modules/addons/outputs.tf
#       └── terraform/outputs.tf (exibe airflow_namespace e status dos releases
#                                  no terminal ao final do apply)
# =============================================================================

output "airflow_namespace" {
  description = "Namespace Kubernetes onde o Airflow foi instalado. Usado em comandos kubectl: kubectl get pods -n <namespace>."
  value       = kubernetes_namespace.airflow.metadata[0].name
}

output "airflow_helm_status" {
  description = "Status do Helm release do Airflow. Valor esperado após apply bem-sucedido: 'deployed'."
  value       = helm_release.airflow.status
}

output "lb_controller_helm_status" {
  description = "Status do Helm release do AWS Load Balancer Controller. Valor esperado: 'deployed'."
  value       = helm_release.lb_controller.status
}

output "cluster_autoscaler_helm_status" {
  description = "Status do Helm release do Cluster Autoscaler. Valor esperado: 'deployed'."
  value       = helm_release.cluster_autoscaler.status
}

output "metrics_server_helm_status" {
  description = "Status do Helm release do Metrics Server. Valor esperado: 'deployed'."
  value       = helm_release.metrics_server.status
}