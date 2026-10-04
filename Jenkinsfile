// CI pipeline: build the five images, push them to Amazon ECR, then deploy with Helm to EKS.
// Jenkins prerequisites: Git, Pipeline, Credentials Binding plugins; Docker, AWS CLI, kubectl and Helm on the agent;
// a "Username with password" credential with id `aws-credentials` (AWS access key id / secret access key).
pipeline {
    agent any

    parameters {
        string(name: 'AWS_ACCOUNT_ID', defaultValue: '', description: '12-digit AWS account id that owns the ECR repositories')
        string(name: 'AWS_REGION', defaultValue: 'ap-south-1', description: 'AWS region of ECR and EKS')
        string(name: 'EKS_CLUSTER', defaultValue: 'streamingapp-cluster', description: 'EKS cluster name')
        string(name: 'APP_URL', defaultValue: 'http://streamingapp.local', description: 'Public URL of the app (baked into the React bundle), e.g. http://<ingress-elb-dns>')
        booleanParam(name: 'DEPLOY', defaultValue: true, description: 'Run helm upgrade --install on EKS after pushing images')
    }

    // Poll the repository every 2 minutes so every new commit triggers a build.
    // (Alternatively add a GitHub webhook to <jenkins-url>/github-webhook/ and use githubPush().)
    triggers {
        pollSCM('H/2 * * * *')
    }

    environment {
        REGISTRY  = "${params.AWS_ACCOUNT_ID}.dkr.ecr.${params.AWS_REGION}.amazonaws.com"
        IMAGE_TAG = "1.0.${env.BUILD_NUMBER}"
        AWS_DEFAULT_REGION = "${params.AWS_REGION}"
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
            }
        }

        stage('Install & Build Frontend') {
            steps {
                dir('frontend') {
                    sh 'npm ci || npm install'
                    sh "CI=false REACT_APP_AUTH_API_URL=${params.APP_URL}/api/auth REACT_APP_STREAMING_API_URL=${params.APP_URL}/api/streaming REACT_APP_STREAMING_PUBLIC_URL=${params.APP_URL} REACT_APP_ADMIN_API_URL=${params.APP_URL}/api/admin REACT_APP_CHAT_API_URL=${params.APP_URL}/api/chat REACT_APP_CHAT_SOCKET_URL=${params.APP_URL} npm run build"
                }
            }
        }

        stage('Build Docker Images') {
            steps {
                sh "APP_URL=${params.APP_URL} ./scripts/build-push.sh ${REGISTRY} ${IMAGE_TAG}"
            }
        }

        stage('Push to ECR') {
            steps {
                withCredentials([usernamePassword(credentialsId: 'aws-credentials', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $REGISTRY
                        for svc in auth stream admin chat frontend; do
                          docker push $REGISTRY/streaming-$svc:$IMAGE_TAG
                        done
                    '''
                }
            }
        }

        stage('Deploy to EKS') {
            when { expression { return params.DEPLOY } }
            steps {
                withCredentials([usernamePassword(credentialsId: 'aws-credentials', usernameVariable: 'AWS_ACCESS_KEY_ID', passwordVariable: 'AWS_SECRET_ACCESS_KEY')]) {
                    sh '''
                        aws eks update-kubeconfig --name $EKS_CLUSTER --region $AWS_REGION
                        helm upgrade --install streamingapp ./helm/streamingapp \
                          --set imagePrefix=$REGISTRY \
                          --set services.auth.tag=$IMAGE_TAG \
                          --set services.streaming.tag=$IMAGE_TAG \
                          --set services.admin.tag=$IMAGE_TAG \
                          --set services.chat.tag=$IMAGE_TAG \
                          --set services.frontend.tag=$IMAGE_TAG \
                          --set config.clientUrls=$APP_URL \
                          --set config.streamingPublicUrl=$APP_URL
                        for d in auth streaming admin chat frontend; do
                          kubectl rollout status deploy/$d --timeout=180s
                        done
                    '''
                }
            }
        }
    }

    post {
        success { echo "Build ${env.BUILD_NUMBER} finished: images tagged ${IMAGE_TAG}." }
        failure { echo 'Pipeline failed - check the stage logs above.' }
    }
}
