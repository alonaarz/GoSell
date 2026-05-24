terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
    }
    tls = {
      source = "hashicorp/tls"
    }
  }
}

// Provider (Твій регіон!)
provider "aws" {
  region     = "eu-north-1"
  access_key = var.aws_access_key
  secret_key = var.aws_secret_key
}

// Keys for master to agent connection
resource "tls_private_key" "jenkins_agent" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# ==============================================================================
# МЕРЕЖА (Твої робочі ресурси)
# ==============================================================================

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true # Потрібно для красивих адрес
  tags = {
    Name = "main-vpc"
  }
}

resource "aws_subnet" "main" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = var.a-zone
  map_public_ip_on_launch = true # КРИТИЧНО: без цього в інстансів не буде публічних IP!
  tags = {
    Name = "main-subnet"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "main-igw"
  }
}

resource "aws_route_table" "main" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "main-rt"
  }
}

resource "aws_route_table_association" "main" {
  subnet_id      = aws_subnet.main.id
  route_table_id = aws_route_table.main.id
}

# ==============================================================================
# SECURITY GROUPS (Окремо для Master та Agent)
# ==============================================================================

// Security Group - Master
resource "aws_security_group" "jenkins_master_sg" {
  name        = "MasterSG"
  description = "SG Jenkins Master, web UI, agent traffic"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "master_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.my_ip]
  security_group_id = aws_security_group.jenkins_master_sg.id
  description       = "SSH from specific IP"
}

resource "aws_security_group_rule" "master_http_my_ip" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = [var.my_ip]
  security_group_id = aws_security_group.jenkins_master_sg.id
  description       = "Jenkins UI Port"
}

resource "aws_security_group_rule" "master_http_from_agent" {
  type                     = "ingress"
  from_port                = 8080
  to_port                  = 8080
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.jenkins_agent_sg.id
  security_group_id        = aws_security_group.jenkins_master_sg.id
  description              = "Jenkins agent to master on port 8080"
}

resource "aws_security_group_rule" "master_icmp" {
  type              = "ingress"
  from_port         = 8
  to_port           = 0
  protocol          = "icmp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_master_sg.id
  description       = "Allow ping"
}

resource "aws_security_group_rule" "master_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_master_sg.id
}


// Security Group - Agent
resource "aws_security_group" "jenkins_agent_sg" {
  name        = "JenkinsAgentSG"
  description = "Agent SG, SSH from specific IP, traffic from master"
  vpc_id      = aws_vpc.main.id
}

resource "aws_security_group_rule" "agent_ssh" {
  type              = "ingress"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.my_ip]
  security_group_id = aws_security_group.jenkins_agent_sg.id
  description       = "SSH from my IP"
}

resource "aws_security_group_rule" "agent_front" {
  type              = "ingress"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_agent_sg.id
  description       = "Frontend App"
}

resource "aws_security_group_rule" "agent_back" {
  type              = "ingress"
  from_port         = 8080
  to_port           = 8080
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_agent_sg.id
  description       = "Backend App"
}

resource "aws_security_group_rule" "agent_db" {
  type              = "ingress"
  from_port         = 5022
  to_port           = 5022
  protocol          = "tcp"
  cidr_blocks       = [var.my_ip]
  security_group_id = aws_security_group.jenkins_agent_sg.id
  description       = "Database App Port"
}

resource "aws_security_group_rule" "agent_from_master" {
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.jenkins_master_sg.id
  security_group_id        = aws_security_group.jenkins_agent_sg.id
  description              = "All TCP from Jenkins master"
}

resource "aws_security_group_rule" "agent_icmp" {
  type              = "ingress"
  from_port         = 8
  to_port           = 0
  protocol          = "icmp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_agent_sg.id
  description       = "Allow ping"
}

resource "aws_security_group_rule" "agent_egress" {
  type              = "egress"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.jenkins_agent_sg.id
}

# ==============================================================================
# EC2 ІНСТАНСИ
# ==============================================================================

// Jenkins Master
resource "aws_instance" "jenkins_master" {
  subnet_id              = aws_subnet.main.id
  availability_zone      = var.a-zone
  ami                    = var.ami-id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_master_sg.id]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 15 # Диск збільшено до 15ГБ як у першому коді
    volume_type = "gp2"
    tags = {
      "name" = "root disk"
    }
  }

  tags = {
    Name = "Jenkins-Master"
  }

  user_data = templatefile("files/install_jenkins_master.sh", {
    agent_ip        = aws_instance.jenkins_agent.private_ip
    private_key_pem = tls_private_key.jenkins_agent.private_key_pem
    admin_password  = var.jenkins_admin_password
  })
}

// Jenkins Agent
resource "aws_instance" "jenkins_agent" {
  subnet_id              = aws_subnet.main.id
  availability_zone      = var.a-zone
  ami                    = var.ami-id
  instance_type          = var.instance_type
  key_name               = var.key_name
  vpc_security_group_ids = [aws_security_group.jenkins_agent_sg.id]

  ebs_block_device {
    device_name = "/dev/sda1"
    volume_size = 15
    volume_type = "gp2"
    tags = {
      "name" = "root disk"
    }
  }

  tags = {
    Name = "Jenkins-Agent"
  }

  user_data = templatefile("files/install_jenkins_agent.sh", {
    public_key = tls_private_key.jenkins_agent.public_key_openssh
  })
}

# ==============================================================================
# OUTPUTS
# ==============================================================================

output "jenkins_master_public_ip" {
  value       = aws_instance.jenkins_master.public_ip
  description = "Public IP - Jenkins Master"
}

output "jenkins_agent_public_ip" {
  value       = aws_instance.jenkins_agent.public_ip
  description = "Public IP - Jenkins Agent"
}

output "jenkins_master_private_ip" {
  value       = aws_instance.jenkins_master.private_ip
  description = "Private IP - Jenkins Master"
}