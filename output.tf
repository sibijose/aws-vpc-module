output "vpc_id" {
  value = aws_vpc.vpc.id
}

output "public_subnets" { 
    
  value = flatten([ aws_subnet.public[*].id ])
}

output "private_subnets" { 
    
  value = flatten([ aws_subnet.private[*].id ])
}
