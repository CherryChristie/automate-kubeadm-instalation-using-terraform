terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "5.92.0"
    }
    tls = {
      source = "hashicorp/tls"
      version = "4.0.6"
    }
  }
  backend "s3" {
    bucket = "cloudcore0070"
    key    = "terraform.tfstate"
    region = "us-east-1"
  }
}

provider "aws" {
  region = "us-east-1"
}

# VPC
resource "aws_vpc" "kubeadm_vpc" {
  cidr_block = "10.0.0.0/16"
  enable_dns_hostnames = true
  tags = {
    name = "kubeadm_vpc"
  }
}

# Subnet
resource "aws_subnet" "kubeadm_subnet" {
  vpc_id     = aws_vpc.kubeadm_vpc.id
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "kubeadm_subnet"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "kubeadm_igw" {
  vpc_id = aws_vpc.kubeadm_vpc.id
  tags = {
    Name = "main"
  }
}

# Route Table
resource "aws_route_table" "kubeadm_route_table" {
  vpc_id = aws_vpc.kubeadm_vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.kubeadm_igw.id
  }

  tags = {
    Name = "kubeadm_route_table"
  }
}

# Route Table Association
resource "aws_route_table_association" "kubeadm_rt_association" {
  subnet_id      = aws_subnet.kubeadm_subnet.id
  route_table_id = aws_route_table.kubeadm_route_table.id
}

# Base Security Group
resource "aws_security_group" "kubeadm_base" {
  name = "kubeadm_base"
  description = "Base security group for all nodes"
  vpc_id = aws_vpc.kubeadm_vpc.id

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "kubeadm_base"
  }
}

# Control Plane Security Group
resource "aws_security_group" "kubeadm_control_plane" {
  name = "kubeadm_control_plane"
  description = "Control plane security group"
  vpc_id = aws_vpc.kubeadm_vpc.id

  # Kubernetes API
  ingress {
    description = "Kubernetes API"
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # etcd
  ingress {
    description = "etcd"
    from_port   = 2379
    to_port     = 2380
    protocol    = "tcp"
    self        = true
  }

  # Kubelet API
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  # Flannel
  ingress {
    description = "Flannel"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }

  tags = {
    Name = "kubeadm_control_plane"
  }
}

# Worker Security Group
resource "aws_security_group" "kubeadm_worker" {
  name = "kubeadm_worker"
  description = "Worker node security group"
  vpc_id = aws_vpc.kubeadm_vpc.id

  # Kubelet API
  ingress {
    description = "Kubelet API"
    from_port   = 10250
    to_port     = 10250
    protocol    = "tcp"
    self        = true
  }

  # NodePort Services
  ingress {
    description = "NodePort Services"
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Flannel
  ingress {
    description = "Flannel"
    from_port   = 8472
    to_port     = 8472
    protocol    = "udp"
    self        = true
  }

  tags = {
    Name = "kubeadm_worker"
  }
}

# Key Pair
resource "random_id" "unique_key_name" {
  byte_length = 8
}

resource "tls_private_key" "kubeadm_private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "kubeadm_demo_keyp" {
  key_name   = "gitopskey-${random_id.unique_key_name.hex}"
  public_key = tls_private_key.kubeadm_private_key.public_key_openssh
}

# Control Plane Instance
resource "aws_instance" "kubeadm_control_plane_instance" {
  ami                     = var.kubeadm_ami_id
  instance_type           = "t2.medium"
  key_name                = aws_key_pair.kubeadm_demo_keyp.key_name
  subnet_id               = aws_subnet.kubeadm_subnet.id
  vpc_security_group_ids  = [
    aws_security_group.kubeadm_base.id,
    aws_security_group.kubeadm_control_plane.id
  ]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 14
    volume_type = "gp2"
  }

  user_data = filebase64("install-kubeadm.sh")

  tags = {
    Name = "kubeadm_control_plane_instance"
  }
}

# Worker Instances
resource "aws_instance" "kubeadm_worker_instance" {
  count = 2
  ami   = var.kubeadm_ami_id
  instance_type = "t2.micro"
  key_name     = aws_key_pair.kubeadm_demo_keyp.key_name
  subnet_id    = aws_subnet.kubeadm_subnet.id
  vpc_security_group_ids = [
    aws_security_group.kubeadm_base.id,
    aws_security_group.kubeadm_worker.id
  ]
  associate_public_ip_address = true

  root_block_device {
    volume_size = 14
    volume_type = "gp2"
  }

  user_data = filebase64("install-kubeadm-worker.sh")

  tags = {
    Name = "kubeadm_worker_instance-${count.index}"
  }
}

# Outputs
output "control_plane_public_ip" {
  value = aws_instance.kubeadm_control_plane_instance.public_ip
}

output "worker_public_ips" {
  value = aws_instance.kubeadm_worker_instance[*].public_ip
}

output "ssh_private_key" {
  value     = tls_private_key.kubeadm_private_key.private_key_openssh
  sensitive = true
}