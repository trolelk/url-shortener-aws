output "api_gateway_url" {
  description = "URL API Gateway"
  value       = module.api_gateway.api_gateway_url
}

output "alb_dns_name" {
  description = "DNS load balancera ECS"
  value       = module.ecs.alb_dns_name
}
