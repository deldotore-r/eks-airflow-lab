# eks-airflow-lab

Ambiente de laboratório para estudo de **Amazon EKS** com **Apache Airflow** rodando pipelines ETL em pods Kubernetes, totalmente provisionado via **Terraform**.

Projetado para ser criado e destruído ao final de cada sessão de estudo com `terraform destroy`, mantendo custos mínimos (~$0,25/hora).

---

## Índice

1. [O que este projeto faz](#1-o-que-este-projeto-faz)
2. [Arquitetura](#2-arquitetura)
3. [Pré-requisitos](#3-pré-requisitos)
4. [Estrutura de diretórios](#4-estrutura-de-diretórios)
5. [Módulos Terraform](#5-módulos-terraform)
6. [Como usar](#6-como-usar)
7. [Estimativa de custos](#7-estimativa-de-custos)
8. [Fluxo de uma DAG ETL](#8-fluxo-de-uma-dag-etl)
9. [Destruindo o ambiente](#9-destruindo-o-ambiente)
10. [Perguntas frequentes](#10-perguntas-frequentes)

---

## 1. O que este projeto faz

Este projeto provisiona, do zero, um ambiente Kubernetes na AWS capaz de executar pipelines de dados orquestrados pelo Airflow. O objetivo é simular um ambiente de produção real, mas com configuração mínima viável para fins didáticos.

Ao executar `terraform apply`, os seguintes recursos são criados automaticamente na AWS:

- Uma **VPC** dedicada com subnets públicas e privadas
- Um **cluster EKS** (Kubernetes gerenciado) com um node group de instâncias EC2
- Um banco de dados **RDS PostgreSQL** para armazenar os metadados do Airflow (histórico de execuções, status de tasks, conexões)
- O **Apache Airflow** instalado via Helm, com o `KubernetesExecutor` — cada task da DAG vira um pod independente no cluster
- O **AWS Load Balancer Controller** para expor a UI do Airflow via Application Load Balancer
- O **Cluster Autoscaler** para escalar automaticamente os nodes EC2 conforme a demanda
- O **Metrics Server** para coletar métricas de CPU e memória dos pods

---

## 2. Arquitetura

```
┌─────────────────────────────────────────────────────────┐
│                        AWS Cloud                        │
│                                                         │
│  ┌──────────────────────────────────────────────────┐   │
│  │                    VPC                           │   │
│  │                                                  │   │
│  │  ┌─────────────────┐    ┌─────────────────────┐  │   │
│  │  │  Subnet Pública │    │   Subnet Privada    │  │   │
│  │  │                 │    │                     │  │   │
│  │  │  ┌───────────┐  │    │  ┌───────────────┐  │  │   │
│  │  │  │    ALB    │  │    │  │  EKS Cluster  │  │  │   │
│  │  │  │(Airflow UI│  │    │  │               │  │  │   │
│  │  │  │  :80)     │  │    │  │  ┌─────────┐  │  │  │   │
│  │  │  └─────┬─────┘  │    │  │  │Airflow  │  │  │  │   │
│  │  │        │        │    │  │  │Scheduler│  │  │  │   │
│  │  └────────┼────────┘    │  │  └────┬────┘  │  │  │   │
│  │           │             │  │       │       │  │  │   │
│  │           │             │  │  ┌────▼────┐  │  │  │   │
│  │           └─────────────┼──┼─▶│Airflow │  │  │  │   │
│  │                         │  │  │Webserver│  │  │  │   │
│  │                         │  │  └─────────┘  │  │  │   │
│  │                         │  │               │  │  │   │
│  │                         │  │  ┌─────────┐  │  │  │   │
│  │                         │  │  │ETL Task │  │  │  │   │
│  │                         │  │  │  (Pod)  │  │  │  │   │
│  │                         │  │  └─────────┘  │  │  │   │
│  │                         │  │               │  │  │   │
│  │                         │  └───────┬───────┘  │  │   │
│  │                         │          │          │  │   │
│  │                         │  ┌───────▼────────┐ │  │   │
│  │                         │  │ RDS PostgreSQL │ │  │   │
│  │                         │  │ (Metadados do  │ │  │   │
│  │                         │  │    Airflow)    │ │  │   │
│  │                         │  └────────────────┘ │  │   │
│  │                         └─────────────────────┘  │   │
│  └──────────────────────────────────────────────────┘   │
└─────────────────────────────────────────────────────────┘
```

### Por que KubernetesExecutor?

O Airflow suporta vários executores. O `KubernetesExecutor` é o mais adequado para ambientes de produção em Kubernetes porque:

- Cada task é isolada em seu próprio pod — falhas não contaminam outras tasks
- Recursos (CPU/memória) são alocados por task, não por worker fixo
- O Cluster Autoscaler pode escalar nodes conforme o número de tasks simultâneas
- Cada task pode usar uma imagem Docker diferente se necessário

---

## 3. Pré-requisitos

Todos os itens abaixo devem estar instalados e configurados na sua máquina local (Fedora Linux) antes de executar qualquer comando deste projeto.

### AWS CLI

```bash
# Verificar se está instalado
aws --version

# Verificar se está autenticado
aws sts get-caller-identity
```

A saída do segundo comando deve retornar seu `Account ID` e `UserId`. Se retornar erro, configure com:

```bash
aws configure
```

### Terraform

```bash
# Verificar versão (requerido: >= 1.7)
terraform version
```

Para instalar no Fedora:

```bash
sudo dnf install -y dnf-plugins-core
sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/fedora/hashicorp.repo
sudo dnf install terraform
```

### kubectl

Necessário para interagir com o cluster após a criação.

```bash
# Instalar no Fedora
sudo dnf install kubernetes-client

# Verificar
kubectl version --client
```

### helm

Necessário para inspecionar ou atualizar os charts manualmente.

```bash
# Instalar no Fedora
sudo dnf install helm

# Verificar
helm version
```

### Permissões IAM necessárias

O usuário/role AWS configurado no CLI precisa das seguintes permissões:

- `AmazonEKSFullAccess`
- `AmazonVPCFullAccess`
- `AmazonRDSFullAccess`
- `IAMFullAccess`
- `ElasticLoadBalancingFullAccess`
- `AmazonEC2FullAccess`

> **Atenção:** Em ambiente de estudo, um usuário com `AdministratorAccess` elimina problemas de permissão, mas nunca use isso em produção real.

---

## 4. Estrutura de diretórios

```
eks-airflow-lab/
│
├── README.md                        # Este arquivo
│
├── terraform/                       # Toda a infraestrutura como código
│   ├── main.tf                      # Orquestrador: instancia todos os módulos
│   ├── variables.tf                 # Declaração das variáveis globais
│   ├── outputs.tf                   # Valores exportados após o apply (endpoint, kubeconfig)
│   ├── terraform.tfvars             # Valores concretos das variáveis (não versionar segredos)
│   ├── versions.tf                  # Pinagem de providers e versão do Terraform
│   │
│   └── modules/                     # Módulos independentes por domínio
│       ├── vpc/                     # Rede: VPC, subnets, IGW, route tables, NAT Gateway
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       │
│       ├── eks/                     # Cluster Kubernetes + node group EC2
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   ├── outputs.tf
│       │   └── iam.tf               # Roles e policies IAM do cluster e dos nodes
│       │
│       ├── rds/                     # Banco PostgreSQL para metadados do Airflow
│       │   ├── main.tf
│       │   ├── variables.tf
│       │   └── outputs.tf
│       │
│       └── addons/                  # Helm charts: Airflow, LB Controller, Autoscaler, Metrics
│           ├── main.tf
│           ├── variables.tf
│           └── outputs.tf
│
└── k8s/                             # Manifests Kubernetes auxiliares (fora do Terraform)
    ├── airflow-values.yaml          # Helm values customizados do Airflow
    └── namespaces.yaml              # Namespaces base do cluster
```

### Por que separar em módulos?

Cada módulo é responsável por um domínio de infraestrutura. Isso significa:

- **Isolamento**: um erro no módulo `rds` não impede o `vpc` de funcionar
- **Reuso**: o módulo `vpc` poderia ser reaproveitado em outro projeto sem alterações
- **Clareza**: para entender o que cria o banco de dados, você lê apenas `modules/rds/`
- **Dependências explícitas**: o `main.tf` raiz passa outputs de um módulo como inputs de outro, tornando as dependências visíveis e rastreáveis

### Por que a pasta `k8s/` existe separada do Terraform?

O arquivo `airflow-values.yaml` é editado com frequência durante estudos (ajuste de recursos, variáveis de ambiente, conexões). Mantê-lo fora do Terraform permite modificar configurações do Airflow sem precisar rodar `terraform apply` — basta um `helm upgrade`.

---

## 5. Módulos Terraform

### `modules/vpc`

Cria a rede base do projeto. Todos os outros recursos vivem dentro desta VPC.

| Recurso | Descrição |
|---|---|
| `aws_vpc` | Rede isolada com CIDR `10.0.0.0/16` |
| `aws_subnet` (pública) | Subnet onde o ALB será exposto |
| `aws_subnet` (privada) | Subnet onde os nodes EKS e o RDS ficam |
| `aws_internet_gateway` | Saída para a internet da subnet pública |
| `aws_nat_gateway` | Permite que nodes privados acessem a internet (para pull de imagens Docker) |
| `aws_route_table` | Tabelas de roteamento para público e privado |

### `modules/eks`

Cria o cluster Kubernetes gerenciado e o grupo de nodes EC2.

| Recurso | Descrição |
|---|---|
| `aws_eks_cluster` | Control plane gerenciado pela AWS (etcd, API server, scheduler) |
| `aws_eks_node_group` | Node group com instâncias `t3.medium` on-demand |
| `aws_iam_role` (cluster) | Role que permite ao EKS chamar APIs da AWS |
| `aws_iam_role` (node) | Role que permite aos nodes registrar no cluster e fazer pull de imagens |

### `modules/rds`

Cria o banco PostgreSQL que o Airflow usa para persistir metadados.

| Recurso | Descrição |
|---|---|
| `aws_db_instance` | PostgreSQL `db.t3.micro`, Single-AZ, 20GB gp2 |
| `aws_db_subnet_group` | Agrupa as subnets privadas para o RDS |
| `aws_security_group` | Permite conexão apenas a partir dos nodes EKS na porta 5432 |

### `modules/addons`

Instala os componentes dentro do cluster via Helm.

| Chart | Descrição |
|---|---|
| `apache-airflow` | Scheduler, Webserver, e KubernetesExecutor |
| `aws-load-balancer-controller` | Cria ALBs automaticamente a partir de Ingress resources |
| `cluster-autoscaler` | Escala o node group conforme pods pendentes |
| `metrics-server` | Coleta métricas de CPU/memória — necessário para HPA e Dashboard |

---

## 6. Como usar

### Primeira execução

```bash
# 1. Entrar no diretório Terraform
cd eks-airflow-lab/terraform

# 2. Inicializar: baixa providers e módulos
terraform init

# 3. Revisar o plano de execução (nenhum recurso é criado ainda)
terraform plan

# 4. Criar toda a infraestrutura (~15 minutos)
terraform apply
```

### Configurar o kubectl

Após o `apply`, configure o acesso ao cluster:

```bash
aws eks update-kubeconfig \
  --region us-east-1 \
  --name $(terraform output -raw cluster_name)
```

### Acessar a UI do Airflow

```bash
# Obter o endereço do ALB
kubectl get ingress -n airflow

# Abrir no navegador (aguardar ~2 minutos para o ALB ficar ativo)
```

### Verificar pods do cluster

```bash
# Ver todos os pods
kubectl get pods -A

# Ver pods do Airflow especificamente
kubectl get pods -n airflow
```

---

## 7. Estimativa de custos

Valores de referência para `us-east-1` (março/2026), on-demand, Single-AZ.

| Componente | Especificação | $/hora |
|---|---|---|
| EKS Control Plane | Gerenciado | $0,100 |
| EC2 Nodes | 2× `t3.medium` | $0,083 |
| RDS PostgreSQL | `db.t3.micro`, 20GB | $0,018 |
| NAT Gateway | 1× | $0,045 |
| ALB | 1× | $0,008 |
| **Total** | | **~$0,254/hora** |

Uma sessão de 2 horas custa aproximadamente **$0,51**.

> **Importante:** O custo só é esse se você executar `terraform destroy` ao final de cada sessão. Recursos ociosos acumulam custo normalmente.

---

## 8. Fluxo de uma DAG ETL

Este é o caminho completo que uma execução de pipeline percorre neste ambiente:

```
1. O Airflow Scheduler lê a DAG do repositório de DAGs (S3 ou volume montado)
2. Scheduler detecta que uma task deve ser executada (por schedule ou trigger manual)
3. Scheduler instrui o KubernetesExecutor a criar um novo Pod no cluster
4. O Pod é criado na namespace `airflow` com a imagem Docker da task
5. A task executa (ex: extrai dados de uma API, transforma com pandas, carrega no S3)
6. O Pod termina e reporta sucesso ou falha ao Scheduler via RDS PostgreSQL
7. O Scheduler atualiza o estado da task no banco e avança o fluxo da DAG
```

---

## 9. Destruindo o ambiente

**Execute sempre ao final de cada sessão de estudo.**

```bash
cd eks-airflow-lab/terraform
terraform destroy
```

O comando lista todos os recursos que serão removidos e pede confirmação. Digite `yes` para confirmar.

> **Atenção:** `terraform destroy` remove **todos** os recursos, incluindo o RDS. Dados persistidos no banco são perdidos. Para labs de estudo, isso é intencional.

### Verificar que nada ficou para trás

Após o destroy, verifique no console AWS se não restaram:

- EC2 instances em execução
- Load Balancers ativos
- RDS instances
- NAT Gateways (estes têm custo por hora mesmo sem tráfego)

---

## 10. Perguntas frequentes

**Por que não usar o LocalExecutor em vez do KubernetesExecutor?**

O LocalExecutor executa tasks como subprocessos no mesmo container do Scheduler, sem isolamento. O KubernetesExecutor é mais complexo de configurar, mas é o que você encontrará em produção e é o objetivo deste lab.

**Posso usar este projeto com múltiplas AZs?**

Sim, mas requer ajustes nos módulos `vpc` e `eks` para adicionar subnets em outras AZs e configurar o node group como multi-AZ. Não está no escopo deste lab por questões de custo.

**O estado do Terraform fica onde?**

Por padrão, o state fica em `terraform/terraform.tfstate` localmente. Para uso em equipe ou mais robusto, configure um backend S3 com DynamoDB para lock — mas para labs individuais, o state local é suficiente.

**Como adicionar uma DAG de teste?**

Após o ambiente estar de pé, coloque arquivos `.py` de DAG na localização configurada no `airflow-values.yaml`. O Scheduler detecta novos arquivos automaticamente em até 5 minutos.

**Por que o `terraform.tfvars` não deve ter segredos versionados?**

O arquivo `terraform.tfvars` pode conter senhas do RDS e outros valores sensíveis. Nunca commite este arquivo com dados reais em repositórios Git (públicos ou privados). Use `.gitignore` para excluí-lo ou use o AWS Secrets Manager para injetar segredos em runtime.
