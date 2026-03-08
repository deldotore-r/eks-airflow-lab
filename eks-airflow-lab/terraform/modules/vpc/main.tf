# =============================================================================
# modules/vpc/main.tf
# Cria toda a infraestrutura de rede do projeto:
#
#   VPC
#    ├── Subnet pública  (ALB)
#    │    └── Internet Gateway → Route Table pública
#    └── Subnet privada  (EKS nodes + RDS)
#         └── NAT Gateway → Route Table privada
#
# Fluxo de tráfego:
#   - Entrada externa:  Internet → IGW → Subnet pública → ALB → Nodes (privado)
#   - Saída dos nodes:  Nodes (privado) → NAT GW → IGW → Internet
#     (necessário para pull de imagens Docker e chamadas a APIs externas)
# =============================================================================

# -----------------------------------------------------------------------------
# VPC principal
# -----------------------------------------------------------------------------

resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr

  # Habilita resolução de DNS dentro da VPC.
  # Necessário para que os nodes EKS resolvam endpoints internos da AWS
  # (ex: endpoint do EKS API server, RDS endpoint).
  enable_dns_support = true

  # Permite que instâncias EC2 recebam hostnames DNS internos (ex: ip-10-0-2-5.ec2.internal).
  # Necessário para o EKS registrar os nodes pelo hostname.
  enable_dns_hostnames = true

  tags = {
    Name        = "${var.project}-vpc"
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# Subnet pública — usada pelo ALB
# -----------------------------------------------------------------------------

resource "aws_subnet" "public" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.public_subnet_cidr
  availability_zone = var.availability_zone

  # Instâncias lançadas nesta subnet recebem automaticamente um IP público.
  # Necessário para que o ALB seja acessível pela internet.
  map_public_ip_on_launch = true

  # Tag obrigatória para que o AWS Load Balancer Controller descubra
  # automaticamente em quais subnets criar os ALBs públicos.
  tags = {
    Name                     = "${var.project}-subnet-public"
    Environment              = var.environment
    Project                  = var.project
    "kubernetes.io/role/elb" = "1"
  }
}

# -----------------------------------------------------------------------------
# Subnet privada — usada pelos nodes EKS e pelo RDS
# -----------------------------------------------------------------------------

resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = var.availability_zone

  # Instâncias nesta subnet NÃO recebem IP público.
  # Acesso à internet ocorre apenas via NAT Gateway (saída) — nunca diretamente.
  map_public_ip_on_launch = false

  # Tag obrigatória para que o AWS Load Balancer Controller descubra
  # subnets privadas ao criar ALBs internos (internal-facing).
  tags = {
    Name                              = "${var.project}-subnet-private"
    Environment                       = var.environment
    Project                           = var.project
    "kubernetes.io/role/internal-elb" = "1"

    # Tag necessária para que o Cluster Autoscaler identifique
    # a qual cluster EKS esta subnet pertence.
    "kubernetes.io/cluster/${var.project}" = "shared"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway — porta de entrada/saída da subnet pública para a internet
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "main" {
  # Associa o IGW à VPC. Só pode haver um IGW por VPC.
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project}-igw"
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# Elastic IP para o NAT Gateway
# O NAT Gateway precisa de um IP público fixo para representar
# todo o tráfego de saída dos nodes privados.
# -----------------------------------------------------------------------------

resource "aws_eip" "nat" {
  # "vpc = true" está deprecated nas versões recentes do provider AWS.
  # O correto é usar domain = "vpc".
  domain = "vpc"

  # Garante que o IGW exista antes de alocar o EIP,
  # pois o EIP precisa de uma VPC com gateway ativo para funcionar.
  depends_on = [aws_internet_gateway.main]

  tags = {
    Name        = "${var.project}-nat-eip"
    Environment = var.environment
    Project     = var.project
  }
}

# -----------------------------------------------------------------------------
# NAT Gateway — permite saída à internet para recursos na subnet privada
# Fica NA subnet pública (precisa de IP público), mas serve a subnet privada.
# -----------------------------------------------------------------------------

resource "aws_nat_gateway" "main" {
  # O NAT Gateway recebe o EIP alocado acima como seu IP público fixo.
  allocation_id = aws_eip.nat.id

  # NAT Gateway fica na subnet PÚBLICA — é daqui que ele acessa o IGW.
  subnet_id = aws_subnet.public.id

  tags = {
    Name        = "${var.project}-nat-gw"
    Environment = var.environment
    Project     = var.project
  }

  # Garante ordem correta de criação: IGW deve existir antes do NAT GW.
  depends_on = [aws_internet_gateway.main]
}

# -----------------------------------------------------------------------------
# Route Table pública — direciona tráfego de saída da subnet pública ao IGW
# -----------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  # Rota padrão: qualquer destino (0.0.0.0/0) vai para o Internet Gateway.
  # Isso torna esta route table "pública".
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project}-rt-public"
    Environment = var.environment
    Project     = var.project
  }
}

# Associa a route table pública à subnet pública.
# Sem esta associação, a subnet usaria a route table padrão da VPC (sem rota ao IGW).
resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Route Table privada — direciona tráfego de saída da subnet privada ao NAT GW
# -----------------------------------------------------------------------------

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  # Rota padrão: qualquer destino vai para o NAT Gateway.
  # O NAT GW traduz o IP privado para seu EIP antes de enviar à internet.
  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.main.id
  }

  tags = {
    Name        = "${var.project}-rt-private"
    Environment = var.environment
    Project     = var.project
  }
}

# Associa a route table privada à subnet privada.
resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}