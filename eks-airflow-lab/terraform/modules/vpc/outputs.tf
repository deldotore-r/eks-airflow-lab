# =============================================================================
# modules/vpc/outputs.tf
# Exporta os atributos dos recursos criados neste módulo.
#
# Estes outputs são consumidos pelo main.tf raiz, que os passa como
# variáveis de entrada para os módulos eks, rds e addons.
#
# Fluxo:
#   modules/vpc/outputs.tf
#       └── terraform/main.tf (module.vpc.vpc_id, module.vpc.private_subnet_id ...)
#               ├── module "eks"    (recebe vpc_id, private_subnet_id)
#               ├── module "rds"    (recebe vpc_id, private_subnet_id)
#               └── module "addons" (recebe vpc_id)
# =============================================================================

output "vpc_id" {
  description = "ID da VPC criada. Usado pelos módulos eks e rds para associar recursos à rede correta."
  value       = aws_vpc.main.id
}

output "public_subnet_id" {
  description = "ID da subnet pública. Usado pelo módulo addons para associar o ALB à subnet com acesso externo."
  value       = aws_subnet.public.id
}

output "private_subnet_id" {
  description = "ID da subnet privada. Usado pelos módulos eks (node group) e rds (instância do banco)."
  value       = aws_subnet.private.id
}

output "nat_gateway_id" {
  description = "ID do NAT Gateway. Exportado para fins de diagnóstico e referência em outros módulos se necessário."
  value       = aws_nat_gateway.main.id
}

output "vpc_cidr" {
  description = "CIDR block da VPC. Usado pelo módulo rds para construir regras de Security Group que permitem tráfego de toda a VPC."
  value       = aws_vpc.main.cidr_block
}

