output "load_balancer_url" {
  description = "URL of the load balancer, for accessing the Employee Directory app"
  value       = "http://${aws_lb.app_alb.dns_name}/"
}

output "bastion_ip" {
  description = "IP of the Bastion instance, for use as a SSH jump host"
  value       = length(aws_instance.bastion) > 0 ? aws_instance.bastion[0].public_ip : null
}
