# aws-vpc-module
my vpc module

Reusable Infrastructure with Terraform Modules: Learn How to Leverage AWS.
Introduction
As per the official documentation of HashiCorp, modules are defined as below.

A module is a container for multiple resources that are used together.

Every Terraform configuration has at least one module, known as its root module, which consists of the resources defined in the .tf files in the main working directory.

A module can call other modules, which lets you include the child module’s resources into the configuration in a concise way. Modules can also be called multiple times, either within the same configuration or in separate configurations, allowing resource configurations to be packaged and re-used.



Setting Up Terraform Modules for AWS
In my AWS project, the creation of VPC is one lengthy chunk of code that is used multiple times. So, I decided to make it a module and keep it in repository.

In this repository, module related .tf files are stored. It is not necessary to separate into multiple files, but as a best practice I have separated the code into multiple files based on the functionality.

Your module file should include all of the necessary information to create the resources it defines, including the name of the resource, the configuration and provider information, and any variables you may need.

vpc-module/main.tf

main.tf contains the following code. Let me explain the top-level architecture for the time being.

/*==== vpc ======*/  
/*create vpc in the cidr */  
  
resource "aws_vpc" "vpc" {  
  cidr_block           = var.cidr_vpc  
  enable_dns_hostnames = true  
  enable_dns_support   = true  
  instance_tenancy     = "default"  
    
  tags = {  
    Name = "${var.project}-${var.environment}"  
  }  
}  
  
/*==== IGW ======*/  
/* Create internet gateway for the public subnets and attach with vpc */  
  
resource "aws_internet_gateway" "igw" {  
  vpc_id = aws_vpc.vpc.id  
  
  tags = {  
    Name = "${var.project}-${var.environment}"  
  }  
}  
/*==== Public Subnets ======*/  
/* Creation of Public subnets, one for each availability zone in the region  */  
  
resource "aws_subnet" "public" {  
  count = local.subnets  
  vpc_id                  = aws_vpc.vpc.id  
  cidr_block              = cidrsubnet(var.cidr_vpc, 4, count.index)  
  availability_zone       = data.aws_availability_zones.available.names[count.index]  
  map_public_ip_on_launch = true  
  tags = {  
    Name = "${var.project}-${var.environment}-public${count.index + 1}"  
  }  
}  
  
/*==== Private Subnets ======*/  
/* Creation of Private  subnets, one for each availability zone in the region  */  
  
resource "aws_subnet" "private" {  
  count = local.subnets  
  vpc_id                  = aws_vpc.vpc.id  
  cidr_block              = cidrsubnet(var.cidr_vpc, 4, (count.index + local.subnets))  
  availability_zone       = data.aws_availability_zones.available.names[count.index]  
  map_public_ip_on_launch = false  
  tags = {  
    Name = "${var.project}-${var.environment}-private${count.index + 1}"  
  }  
}  
  
/*==== Elastic IP ======*/  
/* Creation of Elastic IP for  NAT Gateway */  
  
resource "aws_eip" "nat_ip" {  
  
  count = var.enable_nat_gateway ? 1 : 0  
  vpc = true  
}  
  
/*==== Elastic IP Attachment ======*/  
/* Attachment of Elastic IP for the public access of NAT Gateway */  
  
resource "aws_nat_gateway" "nat_gw" {  
  
  count = var.enable_nat_gateway ? 1 : 0  
  allocation_id = aws_eip.nat_ip[count.index].id  
  subnet_id     = aws_subnet.public[2].id  
  
  tags = {  
    Name = "${var.project}-${var.environment}"  
  }  
  
  # To ensure proper ordering, it is recommended to add an explicit dependency  
  # on the Internet Gateway for the VPC.  
  depends_on = [aws_internet_gateway.igw]  
}  
  
/*==== Public Route Table ======*/  
/* Creation of route for public access via the Internet gateway for the vpc */  
  
resource "aws_route_table" "public" {  
  vpc_id = aws_vpc.vpc.id  
  
  route {  
    cidr_block = "0.0.0.0/0"  
    gateway_id = aws_internet_gateway.igw.id  
  }  
  
  tags = {  
    Name = "${var.project}-${var.environment}-public"  
  }  
}  
  
/*==== Private Route Table =======*/  
/*Creation of Private Route Table with route for public access via the NAT gateway */  
  
resource "aws_route_table" "private" {  
    
  vpc_id = aws_vpc.vpc.id  
  tags = {  
    Name = "${var.project}-${var.environment}-private"  
  }  
}  
  
/*==== Private Route for NAT GW =======*/  
/*Creation of Private Route for public access via the NAT gateway */  
  
resource "aws_route" "private_route" {  
  
  route_table_id  = aws_route_table.private.id  
  count = var.enable_nat_gateway ? 1 : 0  
  destination_cidr_block     = "0.0.0.0/0"  
  nat_gateway_id = aws_nat_gateway.nat_gw[count.index].id  
}  
  
/*==== Association Public Route Table ======*/  
/*Association of Public route table with public subnets. */  
  
resource "aws_route_table_association" "public" {  
  count = local.subnets  
  subnet_id      = aws_subnet.public[count.index].id  
  route_table_id = aws_route_table.public.id  
}  
  
/*==== Association Private Route Table ======*/  
/*Association of Private route table with private subnets. */  
  
resource "aws_route_table_association" "private" {  
  count = local.subnets  
  subnet_id      = aws_subnet.private[count.index].id  
  route_table_id = aws_route_table.private.id  
}  
Later in this article, I will analyze the code and identify various components of the code in order to explain some best practices for improving the quality of your code.

Generally speaking the following resources are there in the main.tf file

Creation of VPC.
Create internet gateway for the public subnets and attach with vpc
Creation of Public subnets, one for each availability zone in the region
Creation of Private subnets, one for each availability zone in the region
Creation of Elastic IP for NAT Gateway
Creation of route for public access via the Internet gateway for the vpc
Creation of Private Route Table with route for public access via the NAT gateway
Creation of Private Route for public access via the NAT gateway
Association of Public route table with public subnets.
Association of Private route table with private subnets.
vpc-module/variables.tf

locals {  
  subnets = length(data.aws_availability_zones.available.names)  
}  
variable "cidr_vpc" {}  
variable "project" {  
  default ="demo"  
}  
variable "environment" {}  
variable "enable_nat_gateway" {  
  type = bool  
}
Input variables that are passed as arguments from the root module should be declared as variables in the variables.tf of the module.

cidr block is assigned to var.cidr_vpc variable. var.project name and var.environment name is assigned in the similar fashion. var.enable_nat_gateway has a particular importance in the code logic that will be explained later.

Here, number of availability zones in the region defined in the root module will be calculated and assigned to local.subnets value.

vpc-module/datasource.tf

/*==== aws_availability_zones ======*/  
/*Gathering of AZs in the region. */  
  
data "aws_availability_zones" "available" {  
  state = "available"  
}
Terraform can use data sources to access information defined outside of Terraform, defined by another Terraform configuration, or modified by functions. Here this data.aws_availability_zones gather the list of availability zones in the current region.

vpc-module/outputs.tf

output "vpc_id"{  
  
    value = aws_vpc.vpc.id  
}  
  
output "public_subnets" {  
  
   value = aws_subnet.public[*].id  
}  
  
output "private_subnets" {  
  
   value = aws_subnet.private[*].id  
}  
  
output "nat_gw" {  
    
  value = aws_nat_gateway.nat_gw  
}
Output values make information about your infrastructure available on the command line. Output values are similar to return values in programming languages.

In modules, output values are used to return output values to the parent module. vpc_id points to the newly created VPC by vpc_module. public subnets are passed by the list public_subnets. Moreover, private subnets are passed by the list private_subnets.

Creation of public and private subnets in the vpc_module.
/*==== Public Subnets ======*/  
/* Creation of Public subnets, one for each availability zone in the region  */  
  
resource "aws_subnet" "public" {  
  count = local.subnets  
  vpc_id                  = aws_vpc.vpc.id  
  cidr_block              = cidrsubnet(var.cidr_vpc, 4, count.index)  
  availability_zone       = data.aws_availability_zones.available.names[count.index]  
  map_public_ip_on_launch = true  
  tags = {  
    Name = "${var.project}-${var.environment}-public${count.index + 1}"  
  }  
}
count meta argument is used here to loop and create Public Subnets which is one per availability zone.

Initially, count is assigned with local.subnets value from variables.tf.

locals {  
  subnets = length(data.aws_availability_zones.available.names)  
}
So, count will be equal to the number of availability zones in the region.

For instance count = 3 for “ap-south-1" region.

cidr_block              = cidrsubnet(var.cidr_vpc, 4, count.index)
cidrsubnet() function is used to subnet using 4 bits and in each iteration count will be increased till local.subnet value. count.index will point to the various subnet blocks. We get the address of subnets are assigned to cidr_block in each iteration. resource.aws_subnet will create all the subnets in AWS. map_public_ip_on_launch= true for public subnets.

Furthermore, same logic is applied for the creation of private subnets.

Only difference is the usage of (count.index + local.subnets) in cidrsubnet() function. So,we can select an address block after the address of public subnets.map_public_ip_on_launch= false for private subnets.

Making the code generic by optional NAT Gateway creation.
To achieve this functionality variable “enable_nat_gateway” is assigned declared in the variables.tf as an input from the root module. A .tfvars file is used to turn on and off this variable as it is boolean.

prod.tfvars file in the root module.

cidr_vpc      = "172.16.0.0/16"  
instance_type = "t2.micro"  
environment   = "prod"  
instance_ami  = "ami-0cca134ec43cf708f"  
enable_nat_gateway = true
tfvars files are used to create multiple environments for the project by feeding separate values for the variables declared in it. For instance, we can make enable_nat_gateway either true or false.

Assume if enable_nat_gateway = true, then what will happen to the vpc_module. Let us check it now.

main.tf of the root module will make a call to vpc_module repository.

module "vpc_module" {  
  
    source = "github.com/pratheeshsatheeshkumar/vpc-module"
      
    project = var.project  
    environment = var.environment  
    cidr_vpc = var.cidr_vpc  
    enable_nat_gateway = var.enable_nat_gateway  
}
You can see some input variables which are fed from main.tf of the root module. enble_nat_gateway is fed with value true as well.

vpc-module/main.tf

/*==== Elastic IP ======*/  
/* Creation of Elastic IP for  NAT Gateway */  
  
resource "aws_eip" "nat_ip" {  
  
  count = var.enable_nat_gateway ? 1 : 0  
  vpc = true  
}  
resource aws_eip is used for the creation of Elastic IP for NAT Gateway.

count = var.enable_nat_gateway ? 1 : 0
count meta argument will be = 1 if var.enable_nat_gateway equal to “true” else count =0. Moreover, count=1 means resource.aws_eip will run 1 time and one elastic ip will be created.

if var.enable_nat_gateway =false then elastic IP will not be created.

/*==== NAT GW creation and attachment of EIP ======*/  
/* Attachment of Elastic IP for the public access of NAT Gateway */  
  
resource "aws_nat_gateway" "nat_gw" {  
  
  count = var.enable_nat_gateway ? 1 : 0  
  allocation_id = aws_eip.nat_ip[count.index].id  
  subnet_id     = aws_subnet.public[2].id  
  
  tags = {  
    Name = "${var.project}-${var.environment}"  
  }  
  
  # To ensure proper ordering, it is recommended to add an explicit dependency  
  # on the Internet Gateway for the VPC.  
  depends_on = [aws_internet_gateway.igw]  
}
Here uses the same logic. This block of code gets executed only if enable_nat_gateway =true. No NAT GW creation otherwise.

/*==== Private Route Table =======*/  
/*Creation of Private Route Table with route for public access via the NAT gateway */  
  
resource "aws_route_table" "private" {  
    
  vpc_id = aws_vpc.vpc.id  
  tags = {  
    Name = "${var.project}-${var.environment}-private"  
  }  
}  
  
/*==== Private Route for NAT GW =======*/  
/*Creation of Private Route for public access via the NAT gateway */  
  
resource "aws_route" "private_route" {  
  
  route_table_id  = aws_route_table.private.id  
  count = var.enable_nat_gateway ? 1 : 0  
  destination_cidr_block     = "0.0.0.0/0"  
  nat_gateway_id = aws_nat_gateway.nat_gw[count.index].id  
}
We need an entry of NAT Gateway in the private route table for public access. if our flag is false private route will be created without any route through nat_gateway.

Complete code of main.tf of the root module.

module "vpc_module" {  
  
    source = "/var/vpc_module"  
      
    project = var.project  
    environment = var.environment  
    cidr_vpc = var.cidr_vpc  
    enable_nat_gateway = var.enable_nat_gateway  
}  
  
/*==== Security Group ======*/  
/*Creation of security group for Bastion Server */  
  
resource "aws_security_group" "bastion_sg" {  
  name_prefix = "${var.project}-${var.environment}-"  
  description = "Allow ssh from anywhere"  
  vpc_id      = module.vpc_module.vpc_id  
  
  
  ingress {  
    from_port        = var.bastion_ssh_port  
    to_port          = var.bastion_ssh_port  
    protocol         = "tcp"  
   # prefix_list_ids = [aws_ec2_managed_prefix_list.ip_pool_prefix_list.id]  
    cidr_blocks      = ["0.0.0.0/0"]  
    ipv6_cidr_blocks = ["::/0"]  
  }  
  
  egress {  
    from_port        = 0  
    to_port          = 0  
    protocol         = "-1"  
    cidr_blocks      = ["0.0.0.0/0"]  
    ipv6_cidr_blocks = ["::/0"]  
  }  
  
  tags = {  
    Name = "${var.project}-${var.environment}-bastion-sg"  
  
  }  
  lifecycle {  
    create_before_destroy = true  
  }  
}  
  
/*==== Security Group ======*/  
/*Creation of security group for frontend Server with ssh access from bastion security group*/  
  
resource "aws_security_group" "frontend_sg" {  
  name_prefix = "${var.project}-${var.environment}-"  
  description = "Allow http from anywhere and ssh from bastion-sg"  
   vpc_id      = module.vpc_module.vpc_id  
  
  
  dynamic "ingress" {  
    
    for_each = toset(var.frontend_ports)  
    iterator = port  
    content {  
      
      from_port        = port.value  
      to_port          = port.value  
      protocol         = "tcp"  
      cidr_blocks      = ["0.0.0.0/0"]  
      ipv6_cidr_blocks = ["::/0"]  
   }  
 }  
  
ingress {  
    from_port       = var.frontend_ssh_port  
    to_port         = var.frontend_ssh_port  
    protocol        = "tcp"  
    cidr_blocks     = var.frontend_public_ssh == true ? ["0.0.0.0/0"] : null     
    security_groups = [aws_security_group.bastion_sg.id]  
      
  }  
  
  
  egress {  
    from_port        = 0  
    to_port          = 0  
    protocol         = "-1"  
    cidr_blocks      = ["0.0.0.0/0"]  
    ipv6_cidr_blocks = ["::/0"]  
  }  
  
  tags = {  
    Name = "${var.project}-${var.environment}-frontend-sg"  
  
  }  
  lifecycle {  
    create_before_destroy = true  
  }  
}  
/*==== Security Group ======*/  
/*Creation of security group for backend Server */  
resource "aws_security_group" "backend_sg" {  
  name_prefix = "${var.project}-${var.environment}-"  
  description = "Allow sql from frontend-sg and ssh from bastion-sg"  
   vpc_id      = module.vpc_module.vpc_id  
  
  
  ingress {  
       
    from_port       = var.database_port  
    to_port         = var.database_port  
    protocol        = "tcp"  
    security_groups = [aws_security_group.frontend_sg.id]  
  }  
  
  ingress {  
      
    from_port       = var.backend_ssh_port  
    to_port         = var.backend_ssh_port  
    protocol        = "tcp"  
    cidr_blocks     = var.backend_public_ssh == true ? ["0.0.0.0/0"] : null  
    security_groups = [aws_security_group.bastion_sg.id]  
      
  }  
  
  
  egress {  
    from_port        = 0  
    to_port          = 0  
    protocol         = "-1"  
    cidr_blocks      = ["0.0.0.0/0"]  
    ipv6_cidr_blocks = ["::/0"]  
  }  
  
  tags = {  
    Name = "${var.project}-${var.environment}-backend-sg"  
  
  }  
  lifecycle {  
    create_before_destroy = true  
  }  
    
}  
/*==== Keypair ======*/  
/*Creation of key pair for server access */  
  
resource "aws_key_pair" "ssh_key" {  
  
  key_name   = "${var.project}-${var.environment}"  
  public_key = file("mykey.pub")  
  tags = {  
    Name = "${var.project}-${var.environment}"  
  }  
}  
  
  
/*==== EC2 Instance Launch ======*/  
/*Creation of EC2 instance for bastion server */  
resource "aws_instance" "bastion" {  
  
  ami                         = var.instance_ami  
  instance_type               = var.instance_type  
  key_name                    = aws_key_pair.ssh_key.key_name  
  associate_public_ip_address = true  
  subnet_id                   = module.vpc_module.public_subnets[1]  
  vpc_security_group_ids      = [aws_security_group.bastion_sg.id]  
  user_data                   = file("setup_bastion.sh")  
  user_data_replace_on_change = true  
  
  tags = {  
    Name = "${var.project}-${var.environment}-bastion"  
  }  
}  
/*====Local_file====*/  
/*==== local_file resource creation to save template_file rendered data======*/  
resource "local_file" "frontend_rendered" {  
    content  = data.template_file.setup_frontend.rendered  
    filename = "${path.module}/frontend_rendered.txt"  
}  
  
/*==== EC2 Instance Launch ======*/  
/*Creation of EC2 instance for frontend server */  
resource "aws_instance" "frontend" {  
  
  ami                         = var.instance_ami  
  instance_type               = var.instance_type  
  key_name                    = aws_key_pair.ssh_key.key_name  
  associate_public_ip_address = true  
  subnet_id                   = module.vpc_module.public_subnets[0]  
  vpc_security_group_ids      = [aws_security_group.frontend_sg.id]  
  user_data                   = data.template_file.setup_frontend.rendered  
  user_data_replace_on_change = true  
  
  tags = {  
    Name = "${var.project}-${var.environment}-frontend"  
  }  
    
}  
  
/*====Local_file====*/  
/*==== local_file resource creation to save template_file rendered data======*/  
resource "local_file" "backend_rendered" {  
    content  = data.template_file.setup_backend.rendered  
    filename = "${path.module}/backend_rendered.txt"  
}  
  
  
/*==== EC2 Instance Launch ======*/  
/*Creation of EC2 instance for backend server */  
resource "aws_instance" "backend" {  
  
  ami                         = var.instance_ami  
  instance_type               = var.instance_type  
  key_name                    = aws_key_pair.ssh_key.key_name  
  associate_public_ip_address = false  
  subnet_id                   = module.vpc_module.private_subnets[1]  
  vpc_security_group_ids      = [aws_security_group.backend_sg.id]  
  user_data                   = data.template_file.setup_backend.rendered  
  user_data_replace_on_change = true  
  
  # To ensure proper ordering, it is recommended to add an explicit dependency  
  depends_on = [module.vpc_module.nat_gw]  
  
  tags = {  
    Name = "${var.project}-${var.environment}-backend"  
  }  
}  
/*==== Private Zone  ======*/  
/*Creation of private zone for private domain */  
resource "aws_route53_zone" "private" {  
  name = var.private_domain  
  
  vpc {  
    vpc_id = module.vpc_module.vpc_id  
  }  
}  
  
/*===== Private Zone : A record  ======*/  
/*=====Creation of A record to backend private IP.=====*/  
resource "aws_route53_record" "db" {  
  zone_id = aws_route53_zone.private.zone_id  
  name    = "db.${var.private_domain}"  
  type    = "A"  
  ttl     = 300  
  records = [aws_instance.backend.private_ip]  
}  
  
/*==== Public Zone : A record  ======*/  
/*====Creation of A record to frontend public IP.====*/  
  
resource "aws_route53_record" "wordpress" {  
  zone_id = data.aws_route53_zone.selected.id  
  name    = "wordpress.${var.public_domain}"  
  type    = "A"  
  ttl     = 300  
  records = [aws_instance.frontend.public_ip]  
}  
  
/*==== Prefix_list ======*/  
  
resource "aws_ec2_managed_prefix_list" "ip_pool_prefix_list" {  
  name           = "${var.project}-${var.environment}-ip_pool_prefix_list"  
  address_family = "IPv4"  
  max_entries    = length(var.ip_pool)  
     
  dynamic "entry" {  
    for_each = toset(var.ip_pool)  
    iterator = ip  
     content {  
       cidr  = ip.value  
     }  
  }  
  
  tags = {  
   Name = "${var.project}-${var.environment}-ip_pool_prefix_list"  
  }  
}  
This part of the code is documented in another project repository. You can find it here : Deployment-of-Three-Tier-Architecture-in-AWS-using-Terraform

After creation of the VPC, Subnets and associated resources, control comes back to the root module. ID values of VPCs, Subnets and NAT Gateways are returned back, which are used for the creation of resources like security groups and instances.
