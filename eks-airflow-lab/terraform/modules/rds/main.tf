# =============================================================================
# modules/rds/main.tf
# Cria o banco de dados PostgreSQL usado pelo Airflow para persistir metadados:
# histórico de execuções, status de tasks, conexões, variáveis e usuários.
#
# Recursos criados:
#   - aws_security_group     : controla quem pode conectar ao banco na porta 5432
#   - aws_db_subnet_group    : informa ao RDS em quais subnets ele pode ser criado
#   - aws_db_instance        : a instância PostgreSQL propriamente dita
# =============================================================================

# -----------------------------------------------------------------------------
# Security Group do RDS
# Princípio do menor privilégio: só os nodes EKS podem conectar ao banco.
# -----------------------------------------------------------------------------

resource "aws_security_group" "rds" {
  name        = "${var.project}-rds-sg"
  description = "Permite conexao PostgreSQL apenas a partir dos nodes EKS."
  vpc_id      = var.vpc_id

  # Regra de entrada: aceita conexões na porta 5432 (PostgreSQL)
  # somente a partir do Security Group dos nodes EKS.
  # Usar referência de SG (source_security_group_id) é mais seguro que
  # liberar por CIDR, pois se aplica apenas às instâncias com aquele SG,
  # independentemente do IP que receberem.
  ingress {
    description     = "PostgreSQL a partir dos nodes EKS"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [var.node_security_group_id]
  }

  # Regra de saída: bloqueia todo tráfego de saída do banco.
  # Um banco de dados não precisa iniciar conexões — apenas recebê-las.
  # Remover esta restrição não causaria problemas funcionais, mas
  # seguir o princípio do menor privilégio é boa prática mesmo em labs.
  egress {
    description = "Bloqueia todo trafego de saida"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "${var.project}-rds-sg"
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# DB Subnet Group
# Informa ao RDS em quais subnets ele pode ser provisionado.
# Mesmo com Single-AZ (lab), o RDS exige um subnet group com pelo menos
# uma subnet declarada.
# -----------------------------------------------------------------------------

resource "aws_db_subnet_group" "main" {
  name        = "${var.project}-db-subnet-group"
  description = "Subnet group para o RDS PostgreSQL do projeto ${var.project}."

  # Lista de subnets onde o RDS pode ser criado.
  # No lab usamos apenas a subnet privada (Single-AZ).
  # Em produção multi-AZ, adicionaríamos subnets de outras AZs aqui.
  subnet_ids = [var.private_subnet_id]

  tags = {
    Name        = "${var.project}-db-subnet-group"
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# Instância RDS PostgreSQL
# -----------------------------------------------------------------------------

resource "aws_db_instance" "main" {
  # Identificador único da instância no console AWS.
  identifier = "${var.project}-postgres"

  # Engine e versão do PostgreSQL.
  # PostgreSQL 15 é a versão estável recomendada para Airflow 2.x.
  engine         = "postgres"
  engine_version = "15"

  instance_class        = var.db_instance_class
  allocated_storage     = var.db_allocated_storage

  # Tipo de armazenamento. gp2 é SSD de uso geral — suficiente para lab.
  # Em produção considere gp3 (melhor custo-benefício e IOPS configurável).
  storage_type          = "gp2"

  # Criptografia do disco em repouso com chave gerenciada pela AWS.
  # Boa prática mesmo em lab — sem custo adicional.
  storage_encrypted     = true

  # Credenciais do banco — valores sensíveis vindos do terraform.tfvars.
  db_name  = var.db_name
  username = var.db_username
  password = var.db_password

  # Associa o banco ao subnet group criado acima.
  db_subnet_group_name = aws_db_subnet_group.main.name

  # Associa o Security Group que restringe acesso ao banco.
  vpc_security_group_ids = [aws_security_group.rds.id]

  # false = Single-AZ. Sem réplica standby em outra AZ.
  # Reduz custo pela metade em relação ao Multi-AZ — adequado para lab.
  multi_az = false

  # false = banco não recebe IP público. Acessível apenas dentro da VPC.
  # NUNCA setar como true em produção.
  publicly_accessible = false

  # Janela de manutenção: horário em que a AWS pode aplicar patches ao engine.
  # Definir explicitamente evita janelas em horários inconvenientes.
  maintenance_window = "sun:04:00-sun:05:00"

  # Janela de backup automático. "00:00-01:00" = meia-noite UTC.
  # backup_retention_period = 0 desabilita backups automáticos no lab
  # para reduzir custos de storage. Em produção, use pelo menos 7 dias.
  backup_retention_period = 0
  backup_window           = "00:00-01:00"

  # true  = aplica mudanças de configuração imediatamente (sem janela de manutenção).
  # Útil no lab para não precisar esperar a janela de manutenção ao ajustar parâmetros.
  apply_immediately = true

  # CRÍTICO para o lab: permite que o terraform destroy remova o banco sem erro.
  # Em produção, NUNCA use skip_final_snapshot = true — você perderia os dados.
  # final_snapshot_identifier seria necessário se skip_final_snapshot = false.
  skip_final_snapshot = true

  # false = Terraform não destruirá este recurso acidentalmente.
  # Como é um lab e usamos terraform destroy intencionalmente, deixamos false
  # e controlamos a destruição via skip_final_snapshot acima.
  deletion_protection = false

  tags = {
    Name        = "${var.project}-postgres"
    Environment = var.environment
    Project     = var.project
  }
}