# OpenObserve self-hosted na AWS

Infraestrutura (Terraform) para rodar o [OpenObserve](https://openobserve.ai/) em modo single node na AWS, para um volume pequeno de logs (< 1 GB/dia).

## Arquitetura

- **EC2 `t4g.small`** (Graviton, Amazon Linux 2023) rodando o OpenObserve em Docker.
- **Caddy** na mesma instância, com HTTPS automático (Let's Encrypt) para o domínio configurado.
- **S3** como armazenamento dos dados (Parquet), privado e criptografado.
  - 30 dias no S3 Standard, depois **Glacier Instant Retrieval** (barato e ainda consultável).
  - Apagados após 365 dias (`expire_after_days`).
- **EBS gp3** de 30 GB com os metadados (SQLite); snapshot diário via DLM, 7 retidos.
- Senha root gerada pelo Terraform e guardada no **SSM Parameter Store**.
- Acesso à instância via **SSM Session Manager**, sem SSH.

Custo estimado: ~US$ 32 a 35 por mês.

## Uso

Pré-requisitos: Terraform >= 1.5 e AWS CLI com credenciais válidas.

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars   # edite e-mail e domínio
terraform init
terraform plan -out=tfplan
terraform apply tfplan
```

## Variáveis principais

| Variável | Padrão | Descrição |
|---|---|---|
| `region` | `us-east-2` | Região AWS |
| `instance_type` | `t4g.small` | Tipo da EC2 |
| `root_user_email` | (obrigatória) | Usuário root do OpenObserve |
| `domain` | `""` | Domínio para HTTPS; vazio = só SSM |
| `allowed_cidrs` | `[]` | CIDRs com acesso direto à porta 5080 |
| `cold_after_days` | `30` | Dias até o Glacier Instant Retrieval |
| `expire_after_days` | `0` | Dias até apagar do S3 (0 = nunca) |
| `openobserve_version` | `latest` | Fixe uma versão em produção |

