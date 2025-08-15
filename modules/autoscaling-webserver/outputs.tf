output "alb_dns_name" {
  value       = aws_lb.webserver_alb.dns_name
  description = "The public DNS name of the ALB used to hit the instances"
}

output "alb_security_group_id" {
  value       = aws_security_group.alb_public_sg.id
  description = "The security group ID of the ALB"
}

output "webserver_security_group_id" {
  value       = aws_security_group.webserver_public_access_sg.id
  description = "The security group ID attached to the webserver instances"
}
