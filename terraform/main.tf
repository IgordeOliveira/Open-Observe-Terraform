data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ssm_parameter" "al2023_arm64" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-arm64"
}

locals {
  name        = "openobserve"
  bucket_name = "${local.name}-data-${data.aws_caller_identity.current.account_id}-${var.region}"
  password_ps = "/${local.name}/root-password"
}

# ---------------------------------------------------------------- S3

resource "aws_s3_bucket" "data" {
  bucket = local.bucket_name
}

resource "aws_s3_bucket_public_access_block" "data" {
  bucket                  = aws_s3_bucket.data.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data" {
  bucket = aws_s3_bucket.data.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "data" {
  bucket = aws_s3_bucket.data.id

  rule {
    id     = "cold-storage"
    status = "Enabled"
    filter {}

    transition {
      days          = var.cold_after_days
      storage_class = "GLACIER_IR"
    }

    dynamic "expiration" {
      for_each = var.expire_after_days > 0 ? [1] : []
      content {
        days = var.expire_after_days
      }
    }
  }

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"
    filter {}

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}

# ---------------------------------------------------------------- Senha root

# O OpenObserve exige minúscula, maiúscula, dígito e caractere especial.
# Os especiais evitam $, aspas, barras, # e = (quebram o heredoc / env-file).
resource "random_password" "root" {
  length           = 24
  special          = true
  override_special = "-_.@%+*!"
  min_lower        = 1
  min_upper        = 1
  min_numeric      = 1
  min_special      = 1
}

resource "aws_ssm_parameter" "root_password" {
  name  = local.password_ps
  type  = "SecureString"
  value = random_password.root.result
}

# ---------------------------------------------------------------- IAM

data "aws_iam_policy_document" "assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${local.name}-instance"
  assume_role_policy = data.aws_iam_policy_document.assume.json
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

data "aws_iam_policy_document" "instance" {
  statement {
    actions   = ["s3:ListBucket", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.data.arn]
  }
  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject", "s3:AbortMultipartUpload"]
    resources = ["${aws_s3_bucket.data.arn}/*"]
  }
  statement {
    actions   = ["ssm:GetParameter"]
    resources = [aws_ssm_parameter.root_password.arn]
  }
}

resource "aws_iam_role_policy" "instance" {
  name   = "s3-and-secret"
  role   = aws_iam_role.instance.id
  policy = data.aws_iam_policy_document.instance.json
}

resource "aws_iam_instance_profile" "instance" {
  name = "${local.name}-instance"
  role = aws_iam_role.instance.name
}

# ---------------------------------------------------------------- Rede

resource "aws_security_group" "instance" {
  name        = "${local.name}-sg"
  description = "OpenObserve"
  vpc_id      = data.aws_vpc.default.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_vpc_security_group_ingress_rule" "direct" {
  for_each          = toset(var.allowed_cidrs)
  security_group_id = aws_security_group.instance.id
  description       = "OpenObserve 5080"
  ip_protocol       = "tcp"
  from_port         = 5080
  to_port           = 5080
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "http" {
  count             = var.domain != "" ? 1 : 0
  security_group_id = aws_security_group.instance.id
  description       = "HTTP (ACME + redirect)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "https" {
  count             = var.domain != "" ? 1 : 0
  security_group_id = aws_security_group.instance.id
  description       = "HTTPS"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------- EC2

resource "aws_instance" "this" {
  ami                    = data.aws_ssm_parameter.al2023_arm64.value
  instance_type          = var.instance_type
  subnet_id              = data.aws_subnets.default.ids[0]
  vpc_security_group_ids = [aws_security_group.instance.id]
  iam_instance_profile   = aws_iam_instance_profile.instance.name

  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 2 # containers precisam alcançar o IMDS
  }

  root_block_device {
    volume_type = "gp3"
    volume_size = var.data_volume_size_gb
    encrypted   = true
  }

  user_data = templatefile("${path.module}/user_data.sh.tftpl", {
    region              = var.region
    bucket              = aws_s3_bucket.data.id
    password_param      = local.password_ps
    root_email          = var.root_user_email
    openobserve_version = var.openobserve_version
    domain              = var.domain
  })
  user_data_replace_on_change = true

  tags = {
    Name = local.name
  }

  depends_on = [aws_ssm_parameter.root_password]
}

resource "aws_eip" "this" {
  instance = aws_instance.this.id
  domain   = "vpc"
}

# ---------------------------------------------------------------- Backup do EBS (metadados SQLite)

data "aws_iam_policy_document" "dlm_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["dlm.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "dlm" {
  name               = "${local.name}-dlm"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume.json
}

resource "aws_iam_role_policy_attachment" "dlm" {
  role       = aws_iam_role.dlm.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSDataLifecycleManagerServiceRole"
}

resource "aws_dlm_lifecycle_policy" "snapshots" {
  description        = "Daily snapshot of the OpenObserve disk"
  execution_role_arn = aws_iam_role.dlm.arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["INSTANCE"]
    target_tags = {
      Name = local.name
    }

    schedule {
      name = "daily-7d"
      create_rule {
        interval      = 24
        interval_unit = "HOURS"
        times         = ["06:00"]
      }
      retain_rule {
        count = 7
      }
      copy_tags = true
    }
  }
}
