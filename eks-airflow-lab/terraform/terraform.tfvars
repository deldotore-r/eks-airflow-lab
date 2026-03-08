# =============================================================================
# terraform.tfvars
# Valores concretos das variáveis declaradas em variables.tf.
#
# ATENÇÃO: Este arquivo contém credenciais sensíveis.
# - Nunca versione este arquivo no Git (está no .gitignore).
# - Em caso de comprometimento, rotacione as senhas imediatamente
#   via console AWS (RDS) e helm upgrade (Airflow).
# =============================================================================

# -----------------------------------------------------------------------------
# Geral
# -----------------------------------------------------------------------------

project     = "eks-airflow-lab"
aws_region  = "us-east-1"
environment = "lab"

# -----------------------------------------------------------------------------
# Rede (VPC)
# -----------------------------------------------------------------------------

vpc_cidr            = "10.0.0.0/16"
public_subnet_cidr  = "10.0.1.0/24"
private_subnet_cidr = "10.0.2.0/24"
availability_zone   = "us-east-1a"

# -----------------------------------------------------------------------------
# EKS
# -----------------------------------------------------------------------------

cluster_name       = "eks-airflow-lab"
kubernetes_version = "1.29"
node_instance_type = "t3.medium"
node_desired_size  = 2
node_min_size      = 1
node_max_size      = 4

# -----------------------------------------------------------------------------
# RDS
# Regras para as senhas:
#   - db_password: mínimo 8 caracteres, sem @, /, " ou espaços (limitação do PostgreSQL/RDS)
#   - Recomendado: use letras maiúsculas, minúsculas, números e símbolos como !#$%
# -----------------------------------------------------------------------------

db_instance_class    = "db.t3.micro"
db_allocated_storage = 20
db_name              = "airflow"

# PREENCHA com valores de sua escolha antes de executar terraform apply
db_username = "SUBSTITUA_POR_UM_USUARIO"   # ex: airflow_admin
db_password = "SUBSTITUA_POR_UMA_SENHA"    # ex: Lab@2024!Secure

# -----------------------------------------------------------------------------
# Airflow
# -----------------------------------------------------------------------------

airflow_namespace     = "airflow"
airflow_chart_version = "1.13.1"

# Senha do usuário "admin" na UI do Airflow (http://<alb-endpoint>)
# PREENCHA com valor de sua escolha antes de executar terraform apply
airflow_webserver_password = "SUBSTITUA_POR_UMA_SENHA"  # ex: Airflow@Lab2024!