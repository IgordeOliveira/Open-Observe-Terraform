# OpenObserve self-hosted na AWS

Infraestrutura (Terraform) para rodar o [OpenObserve](https://openobserve.ai/) em modo single node na AWS, para um volume pequeno de logs (< 1 GB/dia).

## Arquitetura

- **EC2 `t4g.medium`** (Graviton, Amazon Linux 2023) rodando o OpenObserve em Docker.
- **Caddy** na mesma instância, com HTTPS automático (Let's Encrypt) para o domínio configurado.
- **S3** como armazenamento dos dados (Parquet), privado e criptografado.
  - 30 dias no S3 Standard, depois **Glacier Instant Retrieval** (barato e ainda consultável).
  - Apagados após 365 dias (`expire_after_days`).
- **EBS gp3** de 30 GB com os metadados (SQLite); snapshot diário via DLM, 7 retidos.
- Senha root gerada pelo Terraform e guardada no **SSM Parameter Store**.
- Acesso à instância via **SSM Session Manager**, sem SSH.

Região: `us-east-2` (a SCP da conta só permite essa região).

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

### Credenciais com `aws login`

O provider AWS 5.x não lê o `login_session` criado pelo `aws login`. Crie um perfil que delega para a CLI via `credential_process` em `~/.aws/config`:

```ini
[profile terraform]
credential_process = aws configure export-credentials --profile default --format process
region = us-east-2
```

E use-o antes de rodar o Terraform:

```powershell
$env:AWS_PROFILE = "terraform"
```

O perfil precisa ser separado do `default`; senão a CLI chama a si mesma em loop.

Depois do `apply`:

1. Crie um registro **A** do domínio apontando para o output `public_ip` (na Cloudflare, com proxy desligado até o certificado ser emitido).
2. Leia a senha root com o comando do output `root_password_command`.
3. Acesse `https://<domain>` com o e-mail definido em `root_user_email`.
4. No OpenObserve, ajuste a retenção de cada stream para 365 dias, alinhada à regra do S3.

Sem domínio, deixe `domain` vazio e use o comando do output `ssm_port_forward_command`.

## Variáveis principais

| Variável | Padrão | Descrição |
|---|---|---|
| `region` | `us-east-2` | Região AWS |
| `instance_type` | `t4g.medium` | Tipo da EC2 |
| `root_user_email` | (obrigatória) | Usuário root do OpenObserve |
| `domain` | `""` | Domínio para HTTPS; vazio = só SSM |
| `allowed_cidrs` | `[]` | CIDRs com acesso direto à porta 5080 |
| `cold_after_days` | `30` | Dias até o Glacier Instant Retrieval |
| `expire_after_days` | `0` | Dias até apagar do S3 (0 = nunca) |
| `openobserve_version` | `latest` | Fixe uma versão em produção |

## Limitações

- Instância única: se cair, o serviço fica fora até ser recriada. Dados no S3 e snapshots permitem recuperar.
- A senha root fica no state do Terraform (local, fora do git).
