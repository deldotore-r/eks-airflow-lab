# =============================================================================
# modules/rds/outputs.tf
# Exporta os atributos da instância RDS para consumo pelo main.tf raiz,
# que os repassa ao módulo addons para configurar a connection string
# do Airflow apontar para este banco.
#
# Fluxo:
#   modules/rds/outputs.tf
#       └── terraform/main.tf (module.rds.db_endpoint, module.rds.db_name ...)
#               └── module "addons" (monta a connection string do Airflow:
#                   postgresql+psycopg2://user:pass@endpoint:5432/dbname)
# =============================================================================

output "db_endpoint" {
  description = "Endpoint de conexão do RDS (hostname:porta). Usado pelo módulo addons para montar a connection string do Airflow. Formato: <identifier>.xxxx.<region>.rds.amazonaws.com:5432"
  value       = aws_db_instance.main.endpoint
}

output "db_host" {
  description = "Hostname do RDS sem a porta. Alguns clientes PostgreSQL exigem host e porta separados."
  value       = aws_db_instance.main.address
}

output "db_port" {
  description = "Porta do PostgreSQL. Sempre 5432 para este projeto."
  value       = aws_db_instance.main.port
}

output "db_name" {
  description = "Nome do banco de dados criado na instância. Usado na connection string do Airflow."
  value       = aws_db_instance.main.db_name
}

output "db_instance_id" {
  description = "Identificador da instância RDS no console AWS. Útil para comandos aws rds describe-db-instances durante diagnóstico."
  value       = aws_db_instance.main.identifier
}