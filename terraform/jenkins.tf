# ==============================================================================
# SECTION 1: AUTOMATED SSH KEY PAIR GENERATION (.pem file)
# ==============================================================================
# Automatically generates an RSA private key, registers it with AWS EC2,
# and downloads the "jenkins-key.pem" file directly to your local terraform folder.

# Step 1: Generate a secure 4096-bit RSA Private Key in memory
resource "tls_private_key" "jenkins_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Step 2: Register the public key with AWS EC2 Key Pairs
resource "aws_key_pair" "jenkins_key_pair" {
  # Name of the key pair in the AWS EC2 console
  key_name   = "onlineboutique-jenkins-key"
  # The OpenSSH public key derived from the private key above
  public_key = tls_private_key.jenkins_key.public_key_openssh

  tags = {
    Name = "onlineboutique-jenkins-key"
  }
}

# Step 3: Automatically download and save the private key as "jenkins-key.pem" on your local computer
resource "local_file" "jenkins_pem" {
  # The local file path where the .pem key will be saved
  filename        = "${path.module}/jenkins-key.pem"
  # The private key content in PEM format
  content         = tls_private_key.jenkins_key.private_key_pem
  # Linux/Unix read-only file permission for SSH keys (chmod 400)
  file_permission = "0400"
}


# ==============================================================================
# SECTION 2: UBUNTU AMI DATA SOURCE
# ==============================================================================
# Dynamically queries AWS to find the latest official Ubuntu 22.04 LTS AMI

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical's official AWS account ID

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}


# ==============================================================================
# SECTION 3: SECURITY GROUP FOR JENKINS SERVER
# ==============================================================================
# Controls inbound and outbound network traffic to your Jenkins EC2 instance

resource "aws_security_group" "jenkins_sg" {
  name        = "onlineboutique-jenkins-sg"
  description = "Security group for Jenkins CI/CD server"
  vpc_id      = aws_vpc.micro-vpc.id

  # Inbound Rule 1: SSH Access (Port 22)
  # Allows you to connect to the EC2 terminal using your jenkins-key.pem file
  ingress {
    description = "SSH terminal access"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Inbound Rule 2: Jenkins Web UI (Port 8080)
  # Allows you to open the Jenkins web dashboard in your browser
  ingress {
    description = "Jenkins Web Dashboard"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound Rule: Allow All Outbound Traffic
  # Allows the server to reach the internet to download packages, pull GitHub code,
  # and push built Docker images to Amazon ECR
  egress {
    description = "Allow all outbound traffic"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "onlineboutique-jenkins-sg"
  }
}


# ==============================================================================
# SECTION 4: IAM ROLE & INSTANCE PROFILE FOR JENKINS
# ==============================================================================
# Grants the Jenkins server AWS permissions directly via an IAM Role so
# Jenkins can push images to ECR without hardcoded AWS Access Keys.

resource "aws_iam_role" "jenkins_role" {
  name = "onlineboutique-jenkins-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action    = "sts:AssumeRole"
        Effect    = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  tags = {
    Name = "onlineboutique-jenkins-role"
  }
}

# Attach ECR policy so Jenkins can authenticate and push Docker images to Amazon ECR
resource "aws_iam_role_policy_attachment" "jenkins_ecr_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryPowerUser"
  role       = aws_iam_role.jenkins_role.name
}

# Attach Systems Manager (SSM) policy for browser-based terminal access
resource "aws_iam_role_policy_attachment" "jenkins_ssm_access" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  role       = aws_iam_role.jenkins_role.name
}

# Wrapper instance profile required to attach IAM role to EC2
resource "aws_iam_instance_profile" "jenkins_profile" {
  name = "onlineboutique-jenkins-profile"
  role = aws_iam_role.jenkins_role.name
}


# ==============================================================================
# SECTION 5: JENKINS EC2 INSTANCE WITH AUTOMATED BOOTSTRAP SCRIPT
# ==============================================================================
# Provisions the virtual machine, attaches the SSH key, configures 30 GB storage,
# and automatically installs Java, Jenkins, Docker, AWS CLI, and Trivy.

resource "aws_instance" "jenkins_server" {
  # Ubuntu 22.04 LTS AMI discovered dynamically
  ami                         = data.aws_ami.ubuntu.id

  # Sized at t3.medium (2 vCPU, 4 GB RAM)
  instance_type               = "t3.medium"

  # Launch inside the first PUBLIC subnet so we can reach the Web UI on port 8080 and SSH
  subnet_id                   = aws_subnet.k8s-pub-sub[0].id

  # Attach the SSH Key Pair created in Section 1
  key_name                    = aws_key_pair.jenkins_key_pair.key_name

  # Attach the security group with port 22 and port 8080 open
  vpc_security_group_ids      = [aws_security_group.jenkins_sg.id]

  # Attach IAM instance profile for passwordless ECR push access
  iam_instance_profile        = aws_iam_instance_profile.jenkins_profile.name

  # Assign a public IPv4 address for SSH and web browser access
  associate_public_ip_address = true

  # Storage Configuration: Sized at 30 GB
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    tags = {
      Name = "onlineboutique-jenkins-disk"
    }
  }

  # Automated installation script on first boot
  user_data = <<-EOF
              #!/bin/bash
              set -e

              # 1. Update OS packages and install prerequisites
              apt-get update -y
              apt-get install -y openjdk-17-jdk git curl unzip wget apt-transport-https gnupg lsb-release

              # 2. Add Jenkins official repository and install Jenkins
              wget -O /usr/share/keyrings/jenkins-keyring.asc https://pkg.jenkins.io/debian-stable/jenkins.io-2023.key
              echo "deb [signed-by=/usr/share/keyrings/jenkins-keyring.asc] https://pkg.jenkins.io/debian-stable binary/" > /etc/apt/sources.list.d/jenkins.list
              apt-get update -y
              apt-get install -y jenkins

              # Enable and start Jenkins system service
              systemctl enable jenkins
              systemctl start jenkins

              # 3. Install Docker Engine
              apt-get install -y docker.io
              systemctl enable docker
              systemctl start docker

              # CRITICAL: Add 'jenkins' and 'ubuntu' system users to the 'docker' group
              # This grants Jenkins permission to run 'docker build' without needing sudo
              usermod -aG docker jenkins
              usermod -aG docker ubuntu

              # Restart Jenkins so it inherits the newly added docker group permissions
              systemctl restart jenkins

              # 4. Install AWS CLI v2 (used to authenticate Jenkins with Amazon ECR)
              curl -s "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "/tmp/awscliv2.zip"
              unzip -q /tmp/awscliv2.zip -d /tmp
              /tmp/aws/install
              rm -rf /tmp/awscliv2.zip /tmp/aws

              # 5. Install Trivy (Container security scanner for Jenkins pipelines)
              wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /usr/share/keyrings/trivy.gpg
              echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" > /etc/apt/sources.list.d/trivy.list
              apt-get update -y
              apt-get install -y trivy
              EOF

  tags = {
    Name = "onlineboutique-jenkins-server"
  }
}
