output "vpc_id" {
  value = aws_vpc.url_shortener_vpc.id
}

output "public_subnet_ids" {
  value = aws_subnet.public_subnets_url_shortener[*].id
}