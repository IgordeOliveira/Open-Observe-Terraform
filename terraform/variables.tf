variable "region" {
  description = "Região AWS. A SCP da conta só permite us-east-2."
  type        = string
  default     = "us-east-2"
}

variable "instance_type" {
  description = "Tipo da EC2 (Graviton). t4g.small = 2 vCPU / 2 GB, suficiente para <1 GB/dia de logs. Se houver OOM, volte para t4g.medium."
  type        = string
  default     = "t4g.small"
}

variable "data_volume_size_gb" {
  description = "Disco raiz (EBS gp3): SO, imagem Docker, SQLite de metadados e cache/WAL local."
  type        = number
  default     = 30
}

variable "openobserve_version" {
  description = "Tag da imagem OpenObserve. Fixe uma versão específica em produção."
  type        = string
  default     = "latest"
}

variable "root_user_email" {
  description = "E-mail do usuário root do OpenObserve."
  type        = string
}

variable "domain" {
  description = "Domínio (ex: logs.exemplo.com) apontando para o IP elástico. Se vazio, não há HTTPS público e o acesso é via SSM port-forward."
  type        = string
  default     = ""
}

variable "allowed_cidrs" {
  description = "CIDRs com acesso direto à porta 5080 (ex: [\"200.1.2.3/32\"]). Vazio = nenhum."
  type        = list(string)
  default     = []
}

variable "cold_after_days" {
  description = "Dias até mover objetos do S3 para Glacier Instant Retrieval (barato, ainda consultável em ms)."
  type        = number
  default     = 30
}

variable "expire_after_days" {
  description = "Dias até apagar dados do S3. 0 = nunca apaga."
  type        = number
  default     = 0
}
