pipeline {
    agent any

    environment {
        AWS_REGION      = 'ap-south-1'
        AWS_ACCOUNT_ID  = credentials('aws-account-id')
        REGISTRY        = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        EKS_CLUSTER     = 'streaming-app-cluster'
        IMAGE_TAG       = "${env.BUILD_NUMBER}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install Backend Services') {
            steps {
                dir('backend/authService') { sh 'npm install' }
                dir('backend/streamingService') { sh 'npm install' }
                dir('backend/adminService') { sh 'npm install' }
                dir('backend/chatService') { sh 'npm install' }
            }
        }

        stage('Install & Build Frontend') {
            steps {
                dir('frontend') {
                    sh 'npm install'
                    sh 'CI=true npm run build'
                }
            }
        }

        stage('Build Docker Images') {
            steps {
                sh "docker build -t ${REGISTRY}/ecom-streamingapp-auth:${IMAGE_TAG} -t ${REGISTRY}/ecom-streamingapp-auth:latest ./backend/authService"
                sh "docker build -t ${REGISTRY}/ecom-streamingapp-streaming:${IMAGE_TAG} -t ${REGISTRY}/ecom-streamingapp-streaming:latest -f ./backend/streamingService/Dockerfile ./backend"
                sh "docker build -t ${REGISTRY}/ecom-streamingapp-admin:${IMAGE_TAG} -t ${REGISTRY}/ecom-streamingapp-admin:latest -f ./backend/adminService/Dockerfile ./backend"
                sh "docker build -t ${REGISTRY}/ecom-streamingapp-chat:${IMAGE_TAG} -t ${REGISTRY}/ecom-streamingapp-chat:latest -f ./backend/chatService/Dockerfile ./backend"
                sh "docker build -t ${REGISTRY}/ecom-streamingapp-frontend:${IMAGE_TAG} -t ${REGISTRY}/ecom-streamingapp-frontend:latest ./frontend"
            }
        }

        stage('Push to ECR') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'aws-credentials', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY
                        for svc in auth streaming admin chat frontend; do
                          docker push ${REGISTRY}/ecom-streamingapp-${svc}:${IMAGE_TAG}
                          docker push ${REGISTRY}/ecom-streamingapp-${svc}:latest
                        done
                    '''
                }
            }
        }

        stage('Deploy to EKS') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'aws-credentials', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_REGION
                        helm upgrade --install streaming-app ./helm/streaming-app \
                          --set registry=$REGISTRY \
                          --set imageTag=$IMAGE_TAG
                    '''
                }
            }
        }
    }

    post {
        success {
            echo 'Deployment to EKS completed successfully.'
        }
        failure {
            echo 'Pipeline failed — check stage logs above.'
        }
    }
}
