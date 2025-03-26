# provider
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

# Internet Gateway (IGW)
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

# Associate Route Table with Subnet
resource "aws_route_table_association" "kubeadm_rt_association" {
  subnet_id      = aws_subnet.kubeadm_subnet.id
  route_table_id = aws_route_table.kubeadm_route_table.id
}

# Security Groups
resource "aws_security_group" "kubeadm_security_group" {
  name = "kubeadm_security_group"
  lifecycle {
    create_before_destroy = true  # Ensures the resource is created before destroying the old one
  }
  tags = {
    name = "kubeadm_security_group"
  }

  ingress {
    description = "Allow HTTPS"
    from_port    = 443
    to_port      = 443
    protocol     = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow HTTP"
    from_port    = 80
    to_port      = 80
    protocol     = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
  }

  ingress {
    description = "Allow SSH"
    from_port    = 22
    to_port      = 22
    protocol     = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0   # Allow all outbound traffic
    to_port     = 0   # Allow all outbound traffic
    protocol    = "-1" # Allows all protocols
    cidr_blocks = ["0.0.0.0/0"] # Allow traffic to any destination
  }
}

resource "aws_security_group" "kubeadm_control_plane" {
  name = "kubeadm_control_plane"
  lifecycle {
    create_before_destroy = true  # Ensures the resource is created before destroying the old one
  }
  tags = {
    name = "kubeadm_control_plane"
  }

  ingress {
    description = "Kubernetes Server"
    from_port    = 6443
    to_port      = 6443
    protocol     = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
  }

  ingress {
    description = "Kubelet Api"
    from_port    = 10250
    to_port      = 10250
    protocol     = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
  }

  ingress {
    description = "kube-scheduler"
    from_port    = 10259
    to_port      = 10259
    protocol     = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
  }

  ingress {
    description = "kube-control-manager"
    from_port    = 10257
    to_port      = 10257
    protocol     = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
  }

  ingress {
    description = "etcd"
    from_port    = 2379
    to_port      = 2380
    protocol     = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "kubeadm_worker_node" {
  name = "kubeadm_worker_node"
  lifecycle {
    create_before_destroy = true  # Ensures the resource is created before destroying the old one
  }

  ingress {
    description = "kublet api"
    from_port    = 10250
    to_port      = 10250
    protocol     = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
  }

  ingress {
    description = "NodePort Services"
    from_port    = 30000
    to_port      = 32767
    protocol     = "tcp"
    cidr_blocks  = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "kubeadm_flannel" {
  name = "kubeam_flannel"
  lifecycle {
    create_before_destroy = true  # Ensures tthe resource is created before destroying the old one
  }
  ingress {
    description = "Master-worker"
    from_port    = 8285
    to_port      = 8285
    protocol     = "udp"
    cidr_blocks  = ["0.0.0.0/0"]
  }

  ingress {
    description = "Master-worker"
    from_port    = 8472
    to_port      = 8472
    protocol     = "udp"
    cidr_blocks  = ["0.0.0.0/0"]
  }
}

# Key Pairs
# Generate a unique ID for the key name
resource "random_id" "unique_key_name" {
  byte_length = 8  # Length of the random string, adjust if necessary
}

# Generate the private key
resource "tls_private_key" "kubeadm_private_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
  

}

# Create a new key pair using the dynamically generated name
resource "aws_key_pair" "kubeadm_demo_keyp" {
  key_name   = "gitopskey-${random_id.unique_key_name.hex}"  # Use unique key name
  public_key = tls_private_key.kubeadm_private_key.public_key_openssh
  

}

# Example EC2 instance using the newly created key pair
resource "aws_instance" "kubeadm_control_plane_instance" {
  ami                     = var.kubeadm_ami_id
  instance_type           = "t2.medium"
  key_name                = aws_key_pair.kubeadm_demo_keyp.key_name  # Use the dynamically created key pair name
  associate_public_ip_address = true
  security_groups         = [
    aws_security_group.kubeadm_control_plane.name,
    aws_security_group.kubeadm_security_group.name,
    aws_security_group.kubeadm_flannel.name
  ]
  
  root_block_device {
    volume_size = 14
    volume_type = "gp2"
  }

  user_data = templatefile("./install-kubeadm.sh", {})
  tags = {
    Name = "kubeadm_control_plane_instance"
  }

}

resource "aws_instance" "kubeadm_worker_instance" {
  count = 2
  ami   = var.kubeadm_ami_id
  instance_type = "t2.micro"
  key_name     = aws_key_pair.kubeadm_demo_keyp.key_name  # Use the dynamicaly created key pair name
  associate_public_ip_address = true
  security_groups = [
    aws_security_group.kubeadm_worker_node.name,
    aws_security_group.kubeadm_security_group.name,
    aws_security_group.kubeadm_flannel.name
  ]
  
  root_block_device {
    volume_size = 14
    volume_type = "gp2"
  }

  user_data = templatefile("./install-kubeadm-worker.sh", {})

  tags = {
    Name = "kubeadm worker instance-${count.index}"
  }


}
