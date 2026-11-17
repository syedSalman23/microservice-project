# ==============================================================================
# SECTION 1: IAM ROLE FOR EKS CLUSTER CONTROL PLANE
# ==============================================================================
# The EKS Control Plane (managed by AWS) needs permission to make calls to other
# AWS services on your behalf, such as managing EC2 instances and network interfaces.

# Create the IAM Role for the EKS Cluster
resource "aws_iam_role" "eks_cluster_role" {
  # Name of the IAM role in the AWS IAM console
  name = "onlineboutique-eks-cluster-role"

  # Trust policy: specifies WHICH service is allowed to assume (use) this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow the Amazon EKS service itself to assume this role
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
      }
    ]
  })

  # Tags to easily identify this resource in AWS
  tags = {
    Name = "onlineboutique-eks-cluster-role"
  }
}

# Attach the Amazon-managed policy "AmazonEKSClusterPolicy" to the cluster role
# This policy grants EKS permissions to manage compute, networking, and load balancers
resource "aws_iam_role_policy_attachment" "eks_cluster_policy" {
  # The Amazon Resource Name (ARN) of the AWS-managed policy
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  # The role we are attaching this policy to
  role       = aws_iam_role.eks_cluster_role.name
}


# ==============================================================================
# SECTION 2: EKS CLUSTER DEFINITION (CONTROL PLANE)
# ==============================================================================
# This creates the Kubernetes Master / Control Plane managed by AWS.

resource "aws_eks_cluster" "micro_eks" {
  # The unique name for your Kubernetes cluster
  name     = "onlineboutique-eks"

  # The ARN of the IAM role created above for the control plane
  role_arn = aws_iam_role.eks_cluster_role.arn

  # The Kubernetes version to deploy (1.37 is current stable LTS)
  version  = "1.37"

  # VPC and Subnet configuration for the cluster control plane
  vpc_config {
    # Combine all public and private subnets from vpc.tf
    # EKS control plane uses these subnets to create Elastic Network Interfaces (ENIs)
    # to communicate with your worker nodes across all Availability Zones
    subnet_ids = concat(aws_subnet.k8s-pub-sub[*].id, aws_subnet.k8s-pri-sub[*].id)

    # Enable private API endpoint (worker nodes communicate with API inside VPC)
    endpoint_private_access = true

    # Enable public API endpoint (allows kubectl access from your laptop or Jenkins)
    endpoint_public_access  = true
  }

  # Ensure the IAM policy is fully attached before AWS tries to create the cluster
  # If the policy is not attached yet, cluster creation fails with an authorization error
  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]

  # Tags for identifying the cluster
  tags = {
    Name = "onlineboutique-eks"
  }
}


# ==============================================================================
# SECTION 3: IAM ROLE FOR EKS WORKER NODES (EC2 INSTANCES)
# ==============================================================================
# The EC2 instances running your microservices need permissions to join the cluster,
# configure networking (AWS VPC CNI), and pull container images from Amazon ECR.

# Create the IAM Role for Worker Nodes
resource "aws_iam_role" "eks_node_role" {
  # Name of the IAM role for worker nodes
  name = "onlineboutique-eks-node-role"

  # Trust policy: allows the EC2 service to assume this role
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        # Allow EC2 instances to assume this role
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      }
    ]
  })

  # Tags for identification
  tags = {
    Name = "onlineboutique-eks-node-role"
  }
}

# Policy 1: Allows worker nodes to connect to and register with the EKS cluster
resource "aws_iam_role_policy_attachment" "eks_worker_node_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
  role       = aws_iam_role.eks_node_role.name
}

# Policy 2: Allows the AWS VPC CNI plugin to allocate private IP addresses to Pods
resource "aws_iam_role_policy_attachment" "eks_cni_policy" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
  role       = aws_iam_role.eks_node_role.name
}

# Policy 3: Allows worker nodes to read and pull Docker images from Amazon ECR
resource "aws_iam_role_policy_attachment" "eks_ecr_read_only" {
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
  role       = aws_iam_role.eks_node_role.name
}


# ==============================================================================
# SECTION 4: EKS MANAGED NODE GROUP (WORKER NODES)
# ==============================================================================
# This provisions and manages the actual EC2 instances where your 12 microservice
# pods will be scheduled and executed.

resource "aws_eks_node_group" "micro_nodes" {
  # The name of the EKS cluster this node group belongs to
  cluster_name    = aws_eks_cluster.micro_eks.name

  # A name for this specific group of worker nodes
  node_group_name = "onlineboutique-node-group"

  # The IAM role ARN created above for worker nodes
  node_role_arn   = aws_iam_role.eks_node_role.arn

  # Subnets where worker nodes will be launched
  # We place worker nodes strictly in PRIVATE subnets for security
  subnet_ids      = aws_subnet.k8s-pri-sub[*].id

  # EC2 instance sizing
  # t3.large (2 vCPU, 8 GB RAM) is recommended because 12 microservices + redis + monitoring
  # require at least 8-16 GB total cluster memory and enough ENI IPs for ~25-30 total pods
  instance_types  = ["t3.large"]

  # Pricing model: ON_DEMAND for stability (or SPOT for 70% cost savings in testing)
  capacity_type   = "ON_DEMAND"

  # Scaling configuration for the Auto Scaling Group backing the nodes
  scaling_config {
    # Number of worker nodes to launch initially
    desired_size = 2
    # Maximum number of worker nodes allowed during traffic spikes
    max_size     = 4
    # Minimum number of worker nodes that must always be running
    min_size     = 1
  }

  # Rolling update strategy: how many nodes can be unavailable during upgrades
  update_config {
    # Only 1 node is replaced at a time during cluster/node upgrades
    max_unavailable = 1
  }

  # Ensure all 3 IAM policies are attached BEFORE AWS attempts to launch EC2 nodes
  # If policies are missing when nodes boot, nodes cannot join the EKS cluster
  depends_on = [
    aws_iam_role_policy_attachment.eks_worker_node_policy,
    aws_iam_role_policy_attachment.eks_cni_policy,
    aws_iam_role_policy_attachment.eks_ecr_read_only
  ]

  # Tags for worker nodes
  tags = {
    Name = "onlineboutique-worker-node"
  }
}
