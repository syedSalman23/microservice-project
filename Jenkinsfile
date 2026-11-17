// ==============================================================================
// JENKINS DECLARATIVE CI/CD PIPELINE (MONOREPO AUTO-DETECTION)
// ==============================================================================
// This pipeline automatically detects which of the 12 microservices changed
// in your Git commit, then builds, scans, and pushes only that service to AWS ECR,
// and finally updates the Kubernetes manifest tag for Argo CD GitOps delivery.

pipeline {
    // Run this pipeline on any available executor on the Jenkins EC2 server
    agent any

    // ==========================================================================
    // PIPELINE PARAMETERS (Supports both Auto-Detection & Manual Trigger)
    // ==========================================================================
    parameters {
        // Allows you to choose "auto-detect" (default) or pick a specific service manually from the UI
        choice(
            name: 'TARGET_SERVICE',
            choices: [
                'auto-detect',
                'frontend',
                'cartservice',
                'productcatalogservice',
                'currencyservice',
                'paymentservice',
                'shippingservice',
                'emailservice',
                'checkoutservice',
                'recommendationservice',
                'adservice',
                'loadgenerator',
                'shoppingassistantservice',
                'all'
            ],
            description: 'Select "auto-detect" for path-based build, or choose a specific service to build manually'
        )
        // Checkbox option to run security scan with Trivy
        booleanParam(
            name: 'RUN_TRIVY_SCAN',
            defaultValue: true,
            description: 'Check to run Trivy container vulnerability scanner before pushing to ECR'
        )
    }

    // ==========================================================================
    // GLOBAL ENVIRONMENT VARIABLES
    // ==========================================================================
    environment {
        // AWS Region where your ECR repositories exist
        AWS_REGION       = 'ap-south-1'
        
        // Dynamically fetch your 12-digit AWS Account ID using the AWS CLI
        // (Runs without credentials because Jenkins EC2 instance has an IAM role attached!)
        AWS_ACCOUNT_ID   = sh(script: 'aws sts get-caller-identity --query Account --output text', returnStdout: true).trim()
        
        // Fully qualified Amazon ECR Registry URL (e.g., 123456789012.dkr.ecr.ap-south-1.amazonaws.com)
        ECR_REGISTRY     = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        
        // Unique image tag using the Jenkins build number (e.g., build-5)
        IMAGE_TAG        = "build-${BUILD_NUMBER}"
        
        // Jenkins credential ID configured in Jenkins Dashboard for pushing updated YAML manifests back to GitHub
        GIT_CREDENTIALS  = 'github-credentials'
    }

    // ==========================================================================
    // PIPELINE EXECUTION STAGES
    // ==========================================================================
    stages {

        // ----------------------------------------------------------------------
        // STAGE 1: DETECT CHANGED MICROSERVICES (PATH-BASED FILTERING)
        // ----------------------------------------------------------------------
        stage('Detect Changed Services') {
            steps {
                script {
                    echo "=========================================================="
                    echo "Checking Git commit diff to detect modified microservices..."
                    echo "=========================================================="

                    // Check if user manually selected a specific service from Jenkins UI
                    if (params.TARGET_SERVICE != 'auto-detect') {
                        if (params.TARGET_SERVICE == 'all') {
                            env.SERVICES_TO_BUILD = "frontend cartservice productcatalogservice currencyservice paymentservice shippingservice emailservice checkoutservice recommendationservice adservice loadgenerator shoppingassistantservice"
                        } else {
                            env.SERVICES_TO_BUILD = params.TARGET_SERVICE
                        }
                        echo "Manual override selected. Will build: ${env.SERVICES_TO_BUILD}"
                    } else {
                        // Use git diff to see which files changed between HEAD and previous commit
                        def diffOutput = sh(
                            script: 'git diff --name-only HEAD~1 HEAD 2>/dev/null || git diff --name-only HEAD',
                            returnStdout: true
                        ).trim().split('\n')

                        echo "Files modified in this commit:\n${diffOutput.join('\n')}"

                        // Master list of all 12 microservices
                        def allServices = [
                            'frontend', 'cartservice', 'productcatalogservice',
                            'currencyservice', 'paymentservice', 'shippingservice',
                            'emailservice', 'checkoutservice', 'recommendationservice',
                            'adservice', 'loadgenerator', 'shoppingassistantservice'
                        ]

                        // Find which service folders were modified in src/<service>/
                        def detectedServices = []
                        for (service in allServices) {
                            for (filePath in diffOutput) {
                                if (filePath.startsWith("src/${service}/")) {
                                    if (!detectedServices.contains(service)) {
                                        detectedServices.add(service)
                                        echo ">> Detected modification in: src/${service}/"
                                    }
                                }
                            }
                        }

                        // Save detected list into an environment variable
                        if (detectedServices.size() > 0) {
                            env.SERVICES_TO_BUILD = detectedServices.join(' ')
                            echo "Identified services to build: ${env.SERVICES_TO_BUILD}"
                        } else {
                            echo "No microservice source code modified in src/. Pipeline will skip container builds."
                            env.SERVICES_TO_BUILD = ""
                        }
                    }
                }
            }
        }

        // ----------------------------------------------------------------------
        // STAGE 2: AUTHENTICATE WITH AMAZON ECR
        // ----------------------------------------------------------------------
        stage('Authenticate to AWS ECR') {
            when {
                // Only run authentication if there are services to build
                expression { env.SERVICES_TO_BUILD != "" }
            }
            steps {
                echo "Logging into Amazon ECR registry: ${ECR_REGISTRY}..."
                // Fetches authorization token from AWS ECR and pipes it to docker login
                // Thanks to IAM Instance Profile, no hardcoded AWS secrets are needed!
                sh """
                    aws ecr get-login-password --region ${AWS_REGION} | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                """
            }
        }

        // ----------------------------------------------------------------------
        // STAGE 3: DOCKER BUILD
        // ----------------------------------------------------------------------
        stage('Docker Build') {
            when {
                expression { env.SERVICES_TO_BUILD != "" }
            }
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(' ')
                    for (service in services) {
                        echo "------------------------------------------------------"
                        echo "Building Docker container for service: ${service}"
                        echo "------------------------------------------------------"

                        // cartservice Dockerfile lives in src/cartservice/src/
                        def contextDir = "src/${service}"
                        if (service == 'cartservice') {
                            contextDir = "src/cartservice/src"
                        }

                        // Build Docker image and tag it with both :build-ID and :latest
                        sh """
                            docker build \
                                -t ${ECR_REGISTRY}/${service}:${IMAGE_TAG} \
                                -t ${ECR_REGISTRY}/${service}:latest \
                                ${contextDir}
                        """
                    }
                }
            }
        }

        // ----------------------------------------------------------------------
        // STAGE 4: TRIVY SECURITY VULNERABILITY SCAN
        // ----------------------------------------------------------------------
        stage('Security Scan (Trivy)') {
            when {
                expression { env.SERVICES_TO_BUILD != "" && params.RUN_TRIVY_SCAN == true }
            }
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(' ')
                    for (service in services) {
                        echo "Scanning image ${ECR_REGISTRY}/${service}:${IMAGE_TAG} with Trivy..."
                        // Scans container image for CVE security vulnerabilities
                        // --severity HIGH,CRITICAL: focuses on high-risk vulnerabilities
                        // --exit-code 0: generates report without breaking build (change to 1 to enforce strict failure)
                        sh """
                            trivy image \
                                --severity HIGH,CRITICAL \
                                --no-progress \
                                --exit-code 0 \
                                ${ECR_REGISTRY}/${service}:${IMAGE_TAG}
                        """
                    }
                }
            }
        }

        // ----------------------------------------------------------------------
        // STAGE 5: PUSH IMAGES TO AMAZON ECR
        // ----------------------------------------------------------------------
        stage('Push to Amazon ECR') {
            when {
                expression { env.SERVICES_TO_BUILD != "" }
            }
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(' ')
                    for (service in services) {
                        echo "Pushing ${service} image to Amazon ECR..."
                        // Pushes both the versioned tag (build-X) and latest tag
                        sh """
                            docker push ${ECR_REGISTRY}/${service}:${IMAGE_TAG}
                            docker push ${ECR_REGISTRY}/${service}:latest
                        """
                    }
                }
            }
        }

        // ----------------------------------------------------------------------
        // STAGE 6: GITOPS MANIFEST UPDATE (HANDOFF TO ARGO CD)
        // ----------------------------------------------------------------------
        stage('Update GitOps Manifests') {
            when {
                expression { env.SERVICES_TO_BUILD != "" }
            }
            steps {
                script {
                    def services = env.SERVICES_TO_BUILD.split(' ')
                    for (service in services) {
                        echo "Updating image tag in k8s/${service}.yaml to ${IMAGE_TAG}..."

                        // Uses sed to update image tag in the Kubernetes manifest
                        sh """
                            sed -i -E "s|image: .*/${service}:.*|image: ${ECR_REGISTRY}/${service}:${IMAGE_TAG}|g" k8s/${service}.yaml
                        """
                    }

                    echo "Committing updated Kubernetes manifests to Git repository..."
                    // Configures git committer identity and pushes changes back to GitHub
                    // [skip ci] prevents an infinite loop where this commit re-triggers Jenkins
                    sh """
                        git config user.name "jenkins-bot"
                        git config user.email "jenkins-ci@onlineboutique.local"
                        git add k8s/*.yaml
                        git diff-index --quiet HEAD || git commit -m "chore(ci): update image tags to ${IMAGE_TAG} [skip ci]"
                    """

                    // Push commit back to GitHub using Jenkins credentials
                    // (Ensure your GitHub Personal Access Token is saved in Jenkins as 'github-credentials')
                    withCredentials([usernamePassword(credentialsId: env.GIT_CREDENTIALS, usernameVariable: 'GIT_USER', passwordVariable: 'GIT_PASS')]) {
                        sh """
                            git push https://\${GIT_USER}:\${GIT_PASS}@github.com/syedSalman23/microservice-project.git HEAD:\${env.BRANCH_NAME ?: 'dev'}
                        """
                    }

                    echo "GitOps commit complete! Argo CD will detect this commit and synchronize with EKS."
                }
            }
        }
    }

    // ==========================================================================
    // POST-BUILD ACTIONS & CLEANUP
    // ==========================================================================
    post {
        always {
            echo "Cleaning up local dangling Docker images to preserve disk space..."
            // Cleans up untagged image layers left behind during the build
            sh 'docker image prune -f || true'
        }
        success {
            echo "CI/CD Pipeline finished successfully for services: ${env.SERVICES_TO_BUILD}!"
        }
        failure {
            echo "CI/CD Pipeline failed. Please check stage logs above."
        }
    }
}
