# VPC
resource "aws_vpc" "micro-vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name = "k8s-vpc"
  }
}

# Internet Gateway
resource "aws_internet_gateway" "k8s-igw" {
  vpc_id = aws_vpc.micro-vpc.id

  tags = {
    Name = "k8s-igw"
  }
}

# Elastic IP for NAT Gateway
resource "aws_eip" "k8s-nat-eip" {
  domain     = "vpc"
  depends_on = [aws_internet_gateway.k8s-igw]

  tags = {
    Name = "k8s-nat-eip"
  }
}

# NAT Gateway (placed in the first public subnet)
resource "aws_nat_gateway" "k8s-nat" {
  allocation_id = aws_eip.k8s-nat-eip.id
  subnet_id     = aws_subnet.k8s-pub-sub[0].id

  tags = {
    Name = "k8s-nat-gw"
  }

  depends_on = [aws_internet_gateway.k8s-igw]
}

# Public Subnets (across 2 AZs: 10.0.0.0/24 and 10.0.1.0/24)
resource "aws_subnet" "k8s-pub-sub" {
  count                   = 2
  vpc_id                  = aws_vpc.micro-vpc.id
  cidr_block              = "10.0.${count.index}.0/24"
  availability_zone       = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name                     = "k8s-pub-sub-${count.index + 1}"
    "kubernetes.io/role/elb" = "1"
  }
}

# Private Subnets (across 2 AZs: 10.0.10.0/24 and 10.0.11.0/24)
resource "aws_subnet" "k8s-pri-sub" {
  count             = 2
  vpc_id            = aws_vpc.micro-vpc.id
  cidr_block        = "10.0.${count.index + 10}.0/24"
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name                              = "k8s-pri-sub-${count.index + 1}"
    "kubernetes.io/role/internal-elb" = "1"
  }
}

# Route Table for Public Subnets
resource "aws_route_table" "pub-rt" {
  vpc_id = aws_vpc.micro-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.k8s-igw.id
  }

  tags = {
    Name = "k8s-pub-rt"
  }
}

# Route Table for Private Subnets
resource "aws_route_table" "pri_rt" {
  vpc_id = aws_vpc.micro-vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.k8s-nat.id
  }

  tags = {
    Name = "k8s-pri-rt"
  }
}

# Associate Public Subnets with Public Route Table
resource "aws_route_table_association" "pub-sub-assoc" {
  count          = 2
  subnet_id      = aws_subnet.k8s-pub-sub[count.index].id
  route_table_id = aws_route_table.pub-rt.id
}

# Associate Private Subnets with Private Route Table
resource "aws_route_table_association" "pri-sub-assoc" {
  count          = 2
  subnet_id      = aws_subnet.k8s-pri-sub[count.index].id
  route_table_id = aws_route_table.pri_rt.id
}