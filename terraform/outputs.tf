output "instance_id" {
  value = aws_instance.this.id
}

output "public_ip" {
  description = "IP elástico. Se usar domínio, crie um registro A apontando para ele."
  value       = aws_eip.this.public_ip
}

output "url" {
  value = var.domain != "" ? "https://${var.domain}" : "http://${aws_eip.this.public_ip}:5080 (somente se allowed_cidrs liberar seu IP)"
}

output "bucket" {
  value = aws_s3_bucket.data.id
}

output "root_password_command" {
  description = "Comando para ler a senha do usuário root."
  value       = "aws ssm get-parameter --region ${var.region} --name ${local.password_ps} --with-decryption --query Parameter.Value --output text"
}

output "ssm_port_forward_command" {
  description = "Acesso sem expor portas: depois abra http://localhost:5080"
  value       = "aws ssm start-session --region ${var.region} --target ${aws_instance.this.id} --document-name AWS-StartPortForwardingSession --parameters portNumber=5080,localPortNumber=5080"
}
