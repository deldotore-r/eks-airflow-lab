# STUDY_NOTES.md

Registro completo das explicações técnicas produzidas durante a construção do projeto `eks-airflow-lab`, arquivo por arquivo, na ordem em que foram escritos.

Este documento é um complemento ao `README.md`: enquanto o README explica **o que fazer**, este arquivo explica **por que cada decisão foi tomada** e **como cada peça funciona internamente**.

---

## Índice

1. [Decisões de arquitetura](#1-decisões-de-arquitetura)
2. [Custos e instâncias](#2-custos-e-instâncias)
3. [State do Terraform](#3-state-do-terraform)
4. [terraform/versions.tf](#4-terraformversionstf)
5. [terraform/variables.tf](#5-terraformvariablestf)
6. [terraform/terraform.tfvars](#6-terraformterraformtfvars)
7. [.gitignore](#7-gitignore)
8. [terraform/modules/vpc/variables.tf](#8-terraformmodulesvpcvariablestf)
9. [terraform/modules/vpc/main.tf](#9-terraformmodulesvpcmaintf)
10. [terraform/modules/vpc/outputs.tf](#10-terraformmodulesvpcoutputstf)
11. [terraform/modules/eks/variables.tf](#11-terraformmoduleseksvariablestf)
12. [terraform/modules/eks/iam.tf](#12-terraformmoduleseksiamtf)
13. [terraform/modules/eks/main.tf](#13-terraformmoduleseksmaintf)
14. [terraform/modules/eks/outputs.tf](#14-terraformmoduleseksoutputstf)
15. [terraform/modules/rds/variables.tf](#15-terraformmodulesrdsvariablestf)
16. [terraform/modules/rds/main.tf](#16-terraformmodulesrdsmaintf)
17. [terraform/modules/rds/outputs.tf](#17-terraformmodulesrdsoutputstf)
18. [terraform/modules/addons/variables.tf](#18-terraformmodulesaddonsvariablestf)
19. [terraform/modules/addons/main.tf](#19-terraformmodulesaddonsmaintf)
20. [terraform/modules/addons/outputs.tf](#20-terraformmodulesaddonsoutputstf)
21. [terraform/main.tf](#21-terraformmaintf)
22. [terraform/outputs.tf](#22-terraformoutputstf)
23. [k8s/namespaces.yaml](#23-k8snamespacesyaml)
24. [k8s/airflow-values.yaml](#24-k8sairflow-valuesyaml)

---

## 1. Decisões de arquitetura

### Por que separar em módulos?

Cada módulo é responsável por um domínio de infraestrutura. Isso garante:

- **Isolamento**: um erro no módulo `rds` não impede o `vpc` de funcionar
- **Reuso**: o módulo `vpc` poderia ser reaproveitado em outro projeto sem alterações
- **Clareza**: para entender o que cria o banco de dados, você lê apenas `modules/rds/`
- **Dependências explícitas**: o `main.tf` raiz passa outputs de um módulo como inputs de outro, tornando as dependências visíveis e rastreáveis

### Por que KubernetesExecutor no Airflow?

O Airflow suporta vários executores. O `KubernetesExecutor` é o mais adequado para ambientes de produção em Kubernetes porque:

- Cada task é isolada em seu próprio pod — falhas não contaminam outras tasks
- Recursos (CPU/memória) são alocados por task, não por worker fixo
- O Cluster Autoscaler pode escalar nodes conforme o número de tasks simultâneas
- Cada task pode usar uma imagem Docker diferente se necessário

O `LocalExecutor` executa tasks como subprocessos no mesmo container do Scheduler, sem isolamento. É mais simples de configurar, mas não é o que você encontrará em produção.

### Por que a pasta `k8s/` existe separada do Terraform?

O arquivo `airflow-values.yaml` é editado com frequência durante estudos — ajuste de recursos, variáveis de ambiente, conexões. Mantê-lo fora do Terraform permite modificar configurações do Airflow sem precisar rodar `terraform apply`. Basta um `helm upgrade`.

---

## 2. Custos e instâncias

### Estimativa por componente (us-east-1, março/2026, on-demand)

| Componente | Especificação | $/hora | $/minuto |
|---|---|---|---|
| EKS Control Plane | Gerenciado pela AWS | $0,10 | $0,0017 |
| Node Group – EC2 | 2× `t3.medium` (on-demand) | $0,0832 | $0,0014 |
| RDS PostgreSQL | `db.t3.micro`, Single-AZ, 20GB gp2 | $0,018 | $0,0003 |
| NAT Gateway | 1× (tráfego mínimo) | $0,045 | $0,0008 |
| ALB | 1× | $0,008 | $0,0001 |
| **Total** | | **~$0,254/hora** | **~$0,0042/min** |

Uma sessão de 2 horas custa aproximadamente **$0,51**. Um mês com 20 sessões de 2h = **~$10,20** — desde que `terraform destroy` seja executado ao final de cada sessão.

### Por que instâncias on-demand e não Spot?

Instâncias Spot oferecem economia de ~64% no custo de EC2, mas podem ser interrompidas pela AWS com aviso de 2 minutos. Com o `KubernetesExecutor`, uma interrupção Spot mata o pod de task em execução — o Airflow reprocessa, mas para um lab de estudos o comportamento é tolerável. A decisão de usar on-demand foi tomada para simplificar o ambiente e manter o foco no aprendizado, dado que o custo já é baixo.

---

## 3. State do Terraform

### Por que o state remoto existe em produção

| Problema sem state remoto | Solução |
|---|---|
| `terraform.tfstate` no disco local — se a máquina quebra, a infra fica órfã | S3 com versionamento |
| Dois `terraform apply` simultâneos corrompem o state | Lock file (S3 nativo desde Terraform 1.11) |
| State contém senhas em texto claro no disco | S3 com SSE-KMS |
| Sem histórico de mudanças | S3 versioning: cada apply gera nova versão |

### State lock nativo no S3 (Terraform 1.11+)

A partir do Terraform 1.11.0, o locking é feito nativamente no S3, sem DynamoDB. O Terraform cria um arquivo `.tflock` no mesmo local do state file. O argumento `dynamodb_table` foi marcado como deprecated e será removido em versão futura. A configuração moderna é:

```hcl
terraform {
  backend "s3" {
    bucket       = "seu-bucket-de-state"
    key          = "eks-airflow-lab/terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true   # substitui o dynamodb_table
  }
}
```

### Por que este lab usa state local

Configurar o backend S3 via Terraform cria um problema de bootstrap: o bucket precisa existir **antes** do `terraform init`, mas você não quer criar infraestrutura manualmente. A solução padrão é um segundo projeto Terraform só para o backend — o que adiciona complexidade desnecessária para um lab solo. O `.gitignore` já protege o `terraform.tfstate` de ser commitado acidentalmente.

### Atenção: o state contém senhas em texto claro

Mesmo com `sensitive = true` nas variáveis, o Terraform armazena todos os valores no `terraform.tfstate` sem criptografia. Por isso o `.gitignore` cobre tanto o `terraform.tfvars` quanto o `terraform.tfstate`.

---

## 4. `terraform/versions.tf`

**Propósito:** âncora de compatibilidade do projeto.

Sem este arquivo, um `terraform init` resolve os providers na versão mais recente disponível — o que quebra pipelines silenciosamente quando um provider lança uma breaking change.

### Decisões importantes

**`required_version = "~> 1.7"`** — rejeita execuções com Terraform abaixo de 1.7 ou acima de 2.0. O operador `~>` permite patches (1.7.x) mas bloqueia minor incompatíveis (1.8+).

**Cada provider tem `source` + `version`** — o operador `~>` em cada versão permite apenas patches, nunca minor incompatível.

**Provider `tls`** — gera o par de chaves RSA para acesso SSH aos nodes EC2. A chave privada fica no state do Terraform. Em prod, a chave viria de um cofre (Secrets Manager, Vault). No lab, é aceitável.

**Provider `random`** — gera sufixos aleatórios para nomes de recursos que exigem unicidade global na AWS.

---

## 5. `terraform/variables.tf`

**Propósito:** contrato de entrada do projeto. Qualquer valor que o Terraform precisa receber de fora é declarado aqui.

### Decisões importantes

**`sensitive = true`** nas variáveis de senha — o Terraform oculta esses valores em qualquer saída de log, `plan` ou `apply`. Sem isso, senhas aparecem em texto claro no terminal.

**Variáveis sem `default`** (`db_username`, `db_password`, `airflow_webserver_password`) — o Terraform recusa o `apply` se não forem fornecidas. É uma proteção deliberada contra credenciais esquecidas ou hardcoded.

**Blocos separados por domínio** (Geral, VPC, EKS, RDS, Airflow) — facilita localizar e ajustar variáveis de uma camada específica sem varrer o arquivo inteiro.

---

## 6. `terraform/terraform.tfvars`

**Propósito:** único arquivo que precisa ser editado antes do `terraform apply`. Fornece os valores concretos para todas as variáveis declaradas em `variables.tf`.

### Como usar

Procure as três linhas com `SUBSTITUA_POR_...` e preencha com valores de sua escolha:

```hcl
db_username                = "airflow_admin"
db_password                = "SuaSenhaAqui123!"
airflow_webserver_password = "OutraSenhaAqui!"
```

Você inventa esses valores agora, anota em local seguro, e o RDS e o Airflow são criados com eles. Não há nada a "descobrir" — você é quem define.

### Regras para senhas do RDS

- Mínimo 8 caracteres
- Sem `@`, `/`, `"` ou espaços (limitação do PostgreSQL/RDS)
- Recomendado: letras maiúsculas, minúsculas, números e símbolos como `!#$%`

### Três formas de fornecer valores sensíveis

**Opção 1 — `terraform.tfvars`** (usada neste lab): valores escritos diretamente no arquivo, que deve estar no `.gitignore`.

**Opção 2 — variáveis de ambiente**: o Terraform lê automaticamente variáveis com prefixo `TF_VAR_`:
```bash
export TF_VAR_db_password="SuaSenha123!"
terraform apply
```

**Opção 3 — AWS Secrets Manager** (produção real): credenciais armazenadas no Secrets Manager, lidas via data source em tempo de execução. Sem credencial em arquivo ou shell.

---

## 7. `.gitignore`

**Propósito:** protege três categorias críticas de serem commitadas acidentalmente.

### O que é protegido e por quê

**`terraform.tfvars`** — contém senhas e valores sensíveis definidos pelo usuário.

**`terraform.tfstate` e `terraform.tfstate.backup`** — contém o estado real da infraestrutura AWS. Mesmo com `sensitive = true` nas variáveis, o Terraform armazena todos os valores — incluindo senhas — em texto claro no JSON do state.

**`.terraform/`** — diretório de cache dos providers baixados pelo `terraform init`. Chega a centenas de MB e é completamente regenerável com um novo `terraform init`.

---

## 8. `terraform/modules/vpc/variables.tf`

**Propósito:** define a interface de entrada do módulo VPC.

### Decisão de design

Nenhuma variável tem `default`. Módulos reutilizáveis não devem assumir valores — quem os chama (o `main.tf` raiz) é responsável por fornecer tudo explicitamente. Isso torna as dependências visíveis e evita comportamentos implícitos difíceis de rastrear.

O arquivo é intencionalmente enxuto — apenas 6 variáveis, sem lógica. Toda a complexidade de criação dos recursos fica no `main.tf` do módulo.

---

## 9. `terraform/modules/vpc/main.tf`

**Propósito:** cria toda a infraestrutura de rede — VPC, subnets, IGW, NAT Gateway e route tables.

### Fluxo de tráfego

```
Entrada externa:  Internet → IGW → Subnet pública → ALB → Nodes (privado)
Saída dos nodes:  Nodes (privado) → NAT GW → IGW → Internet
```

### Decisões importantes

**Tags `kubernetes.io/role/elb` e `kubernetes.io/role/internal-elb`** nas subnets — sem elas o AWS Load Balancer Controller não consegue descobrir onde criar os ALBs. É um erro silencioso comum: o Ingress fica em estado `pending` indefinidamente.

**Tag `kubernetes.io/cluster/<nome>`** na subnet privada — necessária para o Cluster Autoscaler identificar quais subnets pertencem ao cluster ao escalar novos nodes.

**`domain = "vpc"` no EIP** — substitui o atributo `vpc = true` que foi deprecado no provider AWS 5.x. Usar a forma antiga gera warning e será erro em versões futuras.

**`depends_on` explícito** no NAT Gateway e no EIP — o Terraform infere dependências automaticamente por referências entre recursos, mas quando a dependência é funcional (não de atributo), é necessário declará-la explicitamente para garantir a ordem correta de criação.

**Posição do NAT Gateway** — o NAT Gateway fica na subnet **pública** (precisa de IP público para acessar a internet), mas serve a subnet **privada** (onde os nodes ficam). É um erro comum tentar colocá-lo na subnet privada.

---

## 10. `terraform/modules/vpc/outputs.tf`

**Propósito:** exporta os IDs da VPC e subnets para os módulos `eks`, `rds` e `addons`.

### Decisões importantes

**`vpc_cidr`** — exporta o bloco CIDR da VPC (`10.0.0.0/16`) além do ID. O módulo `rds` usa esse valor para criar regras de Security Group sem precisar hardcodar o CIDR.

**`nat_gateway_id`** — não é consumido por nenhum módulo diretamente, mas é exportado para diagnóstico. Se os nodes não conseguirem fazer pull de imagens Docker, você pode verificar rapidamente se o NAT Gateway está ativo com `terraform output`.

Sem outputs declarados aqui, nenhum outro módulo consegue referenciar o `vpc_id` ou os IDs de subnet, mesmo que os recursos existam.

---

## 11. `terraform/modules/eks/variables.tf`

**Propósito:** define a interface de entrada do módulo EKS.

### Dois grupos distintos de variáveis

**Variáveis de rede** (`vpc_id`, `private_subnet_id`) — não vêm do `terraform.tfvars`. Elas são outputs do módulo VPC repassados pelo `main.tf` raiz. Isso torna a dependência entre os módulos explícita: se o módulo VPC falhar, o Terraform nem tentará criar o EKS.

**Variáveis do node group** (`node_min_size`, `node_max_size`, `node_desired_size`) — os três valores trabalham juntos. O `desired_size` é o ponto de partida na criação; depois disso, o Cluster Autoscaler assume o controle e flutua entre `min` e `max` conforme a demanda de pods.

### Caminho completo dos valores de escalonamento

```
terraform.tfvars
    └── node_desired_size = 2
          │
          ▼
terraform/variables.tf        ← declara as variáveis no escopo raiz
          │
          ▼
terraform/main.tf             ← instancia o módulo eks e passa os valores
          │
          ▼
modules/eks/variables.tf      ← recebe os valores como variáveis locais do módulo
          │
          ▼
modules/eks/main.tf           ← usa var.node_desired_size no aws_eks_node_group
```

---

## 12. `terraform/modules/eks/iam.tf`

**Propósito:** cria as IAM Roles e policies necessárias para o control plane e os nodes EC2 operarem na AWS.

### Conceito-chave: Trust Policy (Assume Role Policy)

Toda IAM Role precisa de uma "trust policy" que define **quem pode assumir** aquela role. Para o EKS, quem assume é o serviço `eks.amazonaws.com`. Para os nodes, quem assume é o serviço `ec2.amazonaws.com`.

### Os dois atores e suas policies

**Role do control plane** — precisa de apenas uma policy (`AmazonEKSClusterPolicy`). A AWS gerencia o resto internamente.

**Role dos nodes** — precisa de quatro policies, cada uma cobrindo um subsistema diferente:

| Policy | Para que serve |
|---|---|
| `AmazonEKSWorkerNodePolicy` | Registrar o node no cluster e interagir com a API do EKS |
| `AmazonEKS_CNI_Policy` | Plugin CNI alocar IPs da VPC para os pods |
| `AmazonEC2ContainerRegistryReadOnly` | Pull de imagens Docker do ECR |
| `CloudWatchAgentServerPolicy` | Publicar logs e métricas no CloudWatch |

A `AmazonEKS_CNI_Policy` é a mais crítica: sem ela o plugin CNI não consegue alocar IPs da VPC para os pods, e o cluster inteiro para de funcionar — pods ficam eternamente em `ContainerCreating`.

**`data "aws_iam_policy_document"`** — em vez de escrever JSON inline, usa este data source para construir a trust policy. O Terraform valida a sintaxe em tempo de `plan`, antes de qualquer recurso ser criado.

---

## 13. `terraform/modules/eks/main.tf`

**Propósito:** cria o cluster EKS gerenciado, o Launch Template e o node group de instâncias EC2.

### Decisões importantes

**`endpoint_public_access = true` + `endpoint_private_access = true`** — a combinação dos dois é necessária para este lab: acesso público permite que seu `kubectl` local alcance o cluster; acesso privado permite que os nodes se comuniquem com o API server dentro da VPC sem sair para a internet.

**IMDSv2 (`http_tokens = "required"`)** — impede um vetor de ataque real em clusters Kubernetes: um pod comprometido poderia fazer uma requisição ao serviço de metadados da instância (`169.254.169.254`) e roubar as credenciais IAM do node. Com IMDSv2, a requisição exige um token de sessão que pods normais não conseguem obter. O `hop_limit = 2` é necessário para que pods legítimos ainda consigam acessar o metadata quando precisam.

**Tags `k8s.io/cluster-autoscaler/*`** no node group — sem elas o Cluster Autoscaler não consegue descobrir qual node group gerenciar. O erro é silencioso: o autoscaler simplesmente não escala nada.

**`depends_on` explícito** em ambos os recursos — o Terraform infere dependências por referência de atributos, mas a relação entre o cluster/nodes e as policy attachments é funcional, não estrutural. Sem o `depends_on`, o Terraform pode paralelizar a criação e tentar subir o cluster antes das permissões estarem prontas.

**`max_unavailable = 1` no `update_config`** — durante um rolling update, no máximo 1 node fica indisponível por vez. Garante que o cluster nunca fique completamente sem capacidade durante atualizações.

---

## 14. `terraform/modules/eks/outputs.tf`

**Propósito:** expõe os atributos do cluster para o módulo `addons` e para o `outputs.tf` raiz.

### Decisões importantes

**`cluster_ca_certificate`** — o certificado da autoridade certificadora do cluster, em base64. Os providers `kubernetes` e `helm` usam esse valor junto com o `cluster_endpoint` para estabelecer uma conexão TLS autenticada com o API server. Sem ele, os providers não conseguem verificar que estão falando com o cluster correto e recusam a conexão.

**`node_security_group_id`** — exporta o security group que o **próprio EKS cria automaticamente** para os nodes (`vpc_config[0].cluster_security_group_id`), não o que criamos manualmente. É esse SG automático que está efetivamente associado às ENIs dos nodes. O módulo `rds` usará esse ID para criar uma regra de entrada que permite apenas tráfego dos nodes EKS na porta 5432.

---

## 15. `terraform/modules/rds/variables.tf`

**Propósito:** define a interface de entrada do módulo RDS.

### Decisões importantes

**`node_security_group_id`** — é o único output do módulo EKS consumido diretamente pelo módulo RDS. Será usado para criar uma regra de ingress no Security Group do banco que aceita conexões **apenas dos nodes EKS**, e não de qualquer recurso dentro da VPC.

**`vpc_cidr`** — exportado pelo módulo VPC e repassado aqui como alternativa mais permissiva nas regras do Security Group, caso necessário durante estudos — sem precisar hardcodar o CIDR `10.0.0.0/16` dentro do módulo.

**`sensitive = true`** em `db_username` e `db_password` — mesmo sendo variáveis internas do módulo, a marcação sensível se propaga: o Terraform não exibirá esses valores em nenhum log de `plan` ou `apply`.

---

## 16. `terraform/modules/rds/main.tf`

**Propósito:** cria o Security Group, o DB Subnet Group e a instância PostgreSQL.

### Decisões importantes

**Regra de ingress por Security Group** — em vez de liberar a porta 5432 para o CIDR `10.0.0.0/16` (toda a VPC), a regra referencia diretamente o SG dos nodes EKS. Isso significa que apenas instâncias com aquele SG associado podem conectar ao banco — independentemente do IP. É uma diferença sutil mas significativa em termos de segurança.

**`skip_final_snapshot = true`** — sem isso, o `terraform destroy` falha e exige que você nomeie um snapshot final antes de deletar o banco. Para um lab destruído rotineiramente, isso seria um obstáculo. Em produção, NUNCA use `skip_final_snapshot = true`.

**`backup_retention_period = 0`** — desabilita backups automáticos. O RDS cobra por storage de backup; em um lab destruído diariamente, esse custo seria desperdício.

**`storage_encrypted = true`** — criptografia em repouso com chave gerenciada pela AWS (AWS Managed Key). Sem custo adicional.

**`multi_az = false`** — Single-AZ reduz o custo pela metade em relação ao Multi-AZ. Adequado para lab, inaceitável para produção com dados críticos.

**`apply_immediately = true`** — aplica mudanças de configuração imediatamente, sem esperar a janela de manutenção. Útil no lab para não precisar aguardar.

---

## 17. `terraform/modules/rds/outputs.tf`

**Propósito:** expõe os atributos de conexão do banco para o módulo `addons`.

### `db_endpoint` vs `db_host`

**`db_endpoint`** retorna o endereço no formato `hostname:5432` — tudo junto. **`db_host`** retorna apenas o hostname, sem a porta. O Airflow monta sua connection string no formato `postgresql+psycopg2://user:pass@host:port/dbname`, então o módulo `addons` usa `db_host` e `db_port` separados — não o `db_endpoint` combinado. Ambos são exportados para flexibilidade.

### Por que `db_username` e `db_password` não são exportados

Eles chegam ao módulo `addons` diretamente do `terraform.tfvars` via `main.tf` raiz, sem passar pelo módulo RDS. Isso evita que credenciais trafeguem por mais módulos do que o necessário, reduzindo a superfície de exposição no state.

---

## 18. `terraform/modules/addons/variables.tf`

**Propósito:** define a interface de entrada do módulo mais dependente do projeto — recebe inputs de três fontes distintas.

### Três fontes de inputs

**Do módulo EKS** — `cluster_name`, `cluster_endpoint`, `cluster_ca_certificate`: não usados para criar recursos AWS, mas para configurar os providers `kubernetes` e `helm` dentro deste módulo. Sem esses valores, todos os Helm releases falham imediatamente.

**Do módulo RDS** — `db_host`, `db_port`, `db_name`: usados para montar a connection string do Airflow.

**Diretamente do `terraform.tfvars`** — `db_username`, `db_password`, `airflow_webserver_password`: chegam aqui sem passar pelo módulo RDS, minimizando a superfície de exposição de credenciais.

---

## 19. `terraform/modules/addons/main.tf`

**Propósito:** instala todos os componentes dentro do cluster via Helm — Metrics Server, AWS Load Balancer Controller, Cluster Autoscaler e Apache Airflow.

### Conceito-chave: IRSA (IAM Roles for Service Accounts)

Usado pelo LB Controller e pelo Cluster Autoscaler. É o mecanismo correto para dar permissões AWS a pods: em vez de ampliar as permissões dos nodes EC2 (o que daria acesso a todos os pods), cada ServiceAccount Kubernetes assume uma IAM Role específica via OIDC. O pod recebe apenas as permissões que precisa.

Sem IRSA, a alternativa seria anexar as policies diretamente à role dos nodes EC2 — o que concederia essas permissões a **todos** os pods rodando naqueles nodes, não apenas ao LB Controller ou ao Autoscaler.

### Decisões importantes

**`postgresql.enabled = false` e `redis.enabled = false`** — o Helm chart do Airflow vem com PostgreSQL e Redis embutidos por padrão. Desabilitar ambos é obrigatório: o PostgreSQL embutido conflitaria com o RDS externo, e o Redis é desnecessário para o `KubernetesExecutor` (que não usa filas Celery).

**`depends_on` no Airflow** — o Ingress do Airflow só será processado corretamente se o LB Controller já estiver rodando quando o chart for instalado. Sem esse `depends_on`, o Terraform pode instalar o Airflow antes do controller estar pronto, e o ALB nunca seria criado.

**`--kubelet-insecure-tls` no Metrics Server** — necessário em alguns clusters EKS onde o kubelet usa certificado auto-assinado. Sem isso, o Metrics Server rejeita a conexão com os nodes e `kubectl top nodes` retorna erro.

**`data "aws_eks_cluster_auth"`** — obtém o token de autenticação temporário para o cluster EKS. O token é gerado pela AWS e tem validade curta (~15 minutos). É equivalente ao que `aws eks get-token` retorna no CLI.

### Ordem de instalação

```
1. kubernetes_namespace.airflow   (sem dependências)
2. helm_release.metrics_server    (sem dependências)
3. helm_release.lb_controller     (depende da IAM role IRSA)
4. helm_release.cluster_autoscaler(depende da IAM role IRSA)
5. helm_release.airflow           (depende do namespace, lb_controller e metrics_server)
```

---

## 20. `terraform/modules/addons/outputs.tf`

**Propósito:** exporta localização e status de saúde dos componentes instalados.

### Status dos Helm releases

O atributo `.status` de um `helm_release` reflete o estado real reportado pelo Helm após a instalação — não apenas se o Terraform terminou sem erro. O valor `deployed` confirma que o chart foi instalado e os recursos Kubernetes foram criados com sucesso. Qualquer outro valor (`failed`, `pending-install`) indica problema e deve ser investigado com:

```bash
helm list -n kube-system
kubectl describe pods -n kube-system
```

---

## 21. `terraform/main.tf`

**Propósito:** orquestrador raiz. Não cria recursos diretamente — instancia os módulos e costura suas dependências.

### Ordem de criação inferida pelo Terraform

```
1. module.vpc      (sem dependências externas)
2. module.eks      (depende de outputs do vpc)
3. module.rds      (depende de outputs do vpc e do eks)
4. module.addons   (depende de outputs do eks e do rds)
```

### Decisões importantes

**Configuração dos providers `kubernetes` e `helm`** — ambos precisam do `cluster_endpoint` e do `cluster_ca_certificate`, mas esses valores só existem após o módulo `eks` ser criado. O Terraform resolve isso porque os providers são configurados com referências (`module.eks.cluster_endpoint`), não com valores estáticos — ele cria o cluster primeiro, resolve os outputs, configura os providers e só então executa o módulo `addons`.

**`base64decode()` no `cluster_ca_certificate`** — o EKS retorna o certificado CA em base64. Os providers `kubernetes` e `helm` esperam o certificado já decodificado. Sem essa chamada, a conexão TLS falha com erro de certificado inválido.

**`default_tags` no provider AWS** — todas as tags declaradas aqui são aplicadas automaticamente a todos os recursos AWS criados, sem precisar repeti-las em cada `resource`. As tags específicas de cada recurso (declaradas nos módulos) são mergeadas com estas.

**Credenciais não passam pelo módulo RDS** — `db_username` e `db_password` são passados diretamente ao módulo `addons` pelo `main.tf` raiz, sem transitar pelo módulo `rds`. Isso minimiza o número de módulos pelo qual as credenciais trafegam.

---

## 22. `terraform/outputs.tf`

**Propósito:** consolida e exibe os valores mais úteis ao final do `terraform apply`.

### Dois propósitos

**Exibição imediata** — o usuário vê os endpoints e comandos prontos para uso no terminal, sem precisar abrir o console AWS.

**Referência programática** — outros sistemas podem chamar `terraform output -raw <nome>` para obter valores em scripts.

### Decisões importantes

**`kubeconfig_command` e `airflow_ui_command`** — em vez de apenas exportar valores brutos, esses outputs entregam comandos prontos para copiar e colar. Eliminam a necessidade de lembrar a sintaxe exata após cada sessão de estudo.

**`helm_status` como mapa** — os quatro status são agrupados em um único output do tipo `map`, produzindo saída organizada:

```
helm_status = {
  airflow            = "deployed"
  cluster_autoscaler = "deployed"
  lb_controller      = "deployed"
  metrics_server     = "deployed"
}
```

**Outputs sensíveis** — senhas são declaradas como outputs com `sensitive = true` para permitir recuperação via `terraform output -raw` durante estudos, mas nunca aparecem automaticamente no terminal após o apply.

---

## 23. `k8s/namespaces.yaml`

**Propósito:** define namespaces auxiliares fora do controle do Terraform.

### Visão completa dos namespaces do cluster

| Namespace | Origem | Uso |
|---|---|---|
| `default` | Kubernetes (automático) | Recursos sem namespace explícito |
| `kube-system` | Kubernetes (automático) | Componentes internos: CoreDNS, kube-proxy |
| `kube-public` | Kubernetes (automático) | Dados públicos do cluster |
| `kube-node-lease` | Kubernetes (automático) | Heartbeats de disponibilidade dos nodes |
| `airflow` | Terraform (módulo addons) | Scheduler, Webserver, pods de task |
| `monitoring` | Este arquivo | Reservado para Prometheus, Grafana, Loki |
| `etl` | Este arquivo | Testes manuais de imagens Docker de pipelines |

### Por que `monitoring` e `etl` ficam fora do Terraform

Esses namespaces são auxiliares — usados durante estudos para experimentos que não fazem parte da infraestrutura principal. Gerenciá-los via Terraform criaria ruído no state e exigiria um `terraform apply` para operações que deveriam ser rápidas e experimentais.

---

## 24. `k8s/airflow-values.yaml`

**Propósito:** Helm values customizados para o Airflow. Arquivo editado com frequência durante estudos.

### Como aplicar após edições

```bash
helm upgrade airflow apache-airflow/airflow \
  --namespace airflow \
  --version 1.13.1 \
  -f k8s/airflow-values.yaml
```

### Decisões importantes

**`AIRFLOW__CORE__LOAD_EXAMPLES: "false"`** — sem isso o Airflow carrega ~20 DAGs de exemplo que poluem a UI e consomem recursos do scheduler desnecessariamente.

**`AIRFLOW__WEBSERVER__EXPOSE_CONFIG: "true"`** — habilita a aba "Configuration" na UI, que mostra todos os parâmetros do `airflow.cfg` em execução. Extremamente útil para aprendizado. Em produção seria desabilitado por expor detalhes de configuração.

**`gitSync` desabilitado com parâmetros documentados** — a seção está comentada com todos os parâmetros necessários para ativar. Quando quiser conectar um repositório de DAGs, basta descomentar e preencher `repo` e `branch`.

**`resources` em todos os componentes** — requests e limits definidos explicitamente evitam que o Scheduler ou Webserver consumam toda a memória de um node, deixando espaço para os pods de task do KubernetesExecutor.

**`logs.persistence.enabled: false`** — logs em `emptyDir` (perdidos quando o pod reinicia). Suficiente para lab. Em produção, use `true` com PVC ou configure um remote logging para S3.

**`redis.enabled: false`** — Redis só é necessário para `CeleryExecutor`. Com `KubernetesExecutor`, o Redis é completamente desnecessário e desabilitá-lo economiza um pod e memória.

### Como sobrescrever recursos por task individual

O `KubernetesExecutor` permite que cada task defina seus próprios recursos via `executor_config` na DAG:

```python
@task(
    executor_config={
        "KubernetesExecutor": {
            "request_memory": "1Gi",
            "request_cpu": "500m",
            "limit_memory": "2Gi",
            "limit_cpu": "1000m",
        }
    }
)
def minha_task_pesada():
    ...
```

Isso substitui os valores padrão definidos em `workers.resources` apenas para aquela task específica.