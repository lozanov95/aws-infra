output "aws_instance_ip" {
  depends_on = [
    aws_instance.web
  ]
  value       = aws_instance.web.public_ip
  description = "EC2's ip"
}

