output "vpc_id" {
  description = "ID of the VPC"
  value       = aws_vpc.main.id
}

output "public_subnet_ids" {
  description = "List of IDs for the public subnets"
  value       = aws_subnet.public[*].id
}

output "private_app_subnet_ids" {
  description = "List of IDs for the private application subnets"
  value       = aws_subnet.private_app[*].id
}

output "private_data_subnet_ids" {
  description = "List of IDs for the private data subnets"
  value       = aws_subnet.private_data[*].id
}

output "private_data_cidr_blocks" {
  description = "CIDR blocks for the private data subnets"
  value       = ["10.0.20.0/24", "10.0.21.0/24"]
}

output "nat_gateway_id" {
  description = "ID of the NAT Gateway"
  value       = aws_nat_gateway.main.id
}
