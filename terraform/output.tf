data "aws_availability_zones" "available" {
  state = "available"
}

output "az_names" {
  description = "List of availability zones in the current region"
  value       = data.aws_availability_zones.available.names
}

output "vpc_id" {
  description = "The ID of the VPC"
  value       = aws_vpc.micro-vpc.id
}

output "public_subnet_ids" {
  description = "IDs of the public subnets"
  value       = aws_subnet.k8s-pub-sub[*].id
}

output "private_subnet_ids" {
  description = "IDs of the private subnets"
  value       = aws_subnet.k8s-pri-sub[*].id
}

output "ecr_repository_urls" {
  description = "Map of repository names to ECR URLs"
  value       = { for k, v in aws_ecr_repository.k8s-repositories : k => v.repository_url }
}

output "eks_cluster_name" {
  description = "Name of the EKS cluster"
  value       = aws_eks_cluster.micro_eks.name
}

output "eks_cluster_endpoint" {
  description = "Endpoint for EKS control plane API"
  value       = aws_eks_cluster.micro_eks.endpoint
}

output "kubeconfig_command" {
  description = "Run this command on your machine to connect kubectl to your new EKS cluster"
  value       = "aws eks update-kubeconfig --region ap-south-1 --name ${aws_eks_cluster.micro_eks.name}"
}

output "jenkins_public_ip" {
  description = "Public IP address of the Jenkins server"
  value       = aws_instance.jenkins_server.public_ip
}

output "jenkins_url" {
  description = "URL to access the Jenkins Web Dashboard"
  value       = "http://${aws_instance.jenkins_server.public_ip}:8080"
}

output "jenkins_ssh_command" {
  description = "Command to SSH into the Jenkins server using the auto-downloaded .pem key"
  value       = "ssh -i jenkins-key.pem ubuntu@${aws_instance.jenkins_server.public_ip}"
}

