# StreamingApp - Deployment Guide

Step-by-step process, from a fresh checkout to a running, scaled, monitored deployment. Sections 1-2 are shared; use section 3 for a local cluster (kind/minikube) or sections 4-8 for AWS (ECR, EKS, Jenkins, CloudWatch).

## 0. Repository layout

```
backend/{authService,streamingService,adminService,chatService}   Node.js services (each ships a Dockerfile)
frontend/                  React SPA + Nginx Dockerfile
helm/streamingapp/         Helm chart (Chart.yaml, values.yaml, templates/)
Jenkinsfile                CI pipeline: build -> ECR -> helm deploy to EKS
eks/cluster.yaml           eksctl cluster definition
scripts/                   build-push.sh, create-ecr-repos.sh, cloudwatch-alarms.sh, smoke-test.sh, kind-cluster.yaml
docs/                      this guide + ARCHITECTURE.md
```

## 1. Version control

```bash
# fork github.com/UnpredictablePrashant/StreamingApp in the GitHub UI, then:
git clone https://github.com/<you>/StreamingApp.git && cd StreamingApp
git remote add upstream https://github.com/UnpredictablePrashant/StreamingApp.git
# keep the fork in sync
git fetch upstream && git merge upstream/main && git push origin main
```

## 2. Containerize

Each service already ships a Dockerfile; the frontend is a multi-stage Node -> Nginx build. `scripts/build-push.sh` builds all five images (the React API URLs are baked in from `APP_URL`).

```bash
APP_URL=http://streamingapp.local ./scripts/build-push.sh <dockerhub-user> 1.0.0 --push
```

Images: `streaming-auth`, `streaming-stream`, `streaming-admin`, `streaming-chat`, `streaming-frontend` (tag `1.0.0`).

## 3. Local cluster (kind) - tested

```bash
kind create cluster --name streamingapp --config scripts/kind-cluster.yaml
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/kind/deploy.yaml
kubectl -n ingress-nginx wait --for=condition=ready pod -l app.kubernetes.io/component=controller --timeout=180s

# use local images instead of Docker Hub
./scripts/build-push.sh local 1.0.0
for s in auth stream admin chat frontend; do kind load docker-image local/streaming-$s:1.0.0 --name streamingapp; done

helm install streamingapp ./helm/streamingapp --set imagePrefix=local --set imagePullPolicy=Never
kubectl rollout status deploy/auth deploy/streaming deploy/admin deploy/chat deploy/frontend
./scripts/smoke-test.sh http://localhost:8080 streamingapp.local
```

Open the UI: add `127.0.0.1 streamingapp.local` to `/etc/hosts`, then browse to `http://streamingapp.local:8080` (build the frontend with `APP_URL=http://streamingapp.local:8080` for the browser to reach the APIs on that port).

> MongoDB 6 needs a CPU with AVX. On older CPUs use `--set mongo.image=mongo:4.4`.

## 4. AWS environment

```bash
aws configure            # access key id, secret, region (ap-south-1), output json
aws sts get-caller-identity
```

Install `eksctl`, `kubectl`, `helm` and Docker on your workstation.

## 5. Amazon ECR

```bash
./scripts/create-ecr-repos.sh ap-south-1
ACCT=$(aws sts get-caller-identity --query Account --output text)
REG=$ACCT.dkr.ecr.ap-south-1.amazonaws.com
aws ecr get-login-password --region ap-south-1 | docker login --username AWS --password-stdin $REG
APP_URL=http://<ingress-hostname> ./scripts/build-push.sh $REG 1.0.0 --push
```

## 6. EKS cluster and deployment

```bash
eksctl create cluster -f eks/cluster.yaml          # ~15-20 min; adds EBS CSI + CloudWatch observability addons
kubectl get nodes

# ingress controller (creates an AWS load balancer)
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/main/deploy/static/provider/aws/deploy.yaml
kubectl -n ingress-nginx get svc ingress-nginx-controller      # note the EXTERNAL-IP / hostname

helm install streamingapp ./helm/streamingapp \
  --set imagePrefix=$REG \
  --set ingress.host=<ingress-elb-hostname> \
  --set config.clientUrls=http://<ingress-elb-hostname> \
  --set config.streamingPublicUrl=http://<ingress-elb-hostname> \
  --set config.awsS3Bucket=<bucket> \
  --set secrets.jwtSecret=$(openssl rand -hex 32) \
  --set secrets.awsAccessKeyId=<key> --set secrets.awsSecretAccessKey=<secret>
```

The frontend image must have been built with the same `APP_URL` as the host you set above. Verify:

```bash
kubectl get pods,svc,ingress -A
./scripts/smoke-test.sh http://<ingress-elb-hostname>
```

## 7. Jenkins CI (EC2)

1. Launch an Ubuntu 22.04 EC2 instance (t3.medium, security group open on 22 and 8080).
2. Install: `openjdk-17-jre`, Jenkins (official apt repo), Docker (`usermod -aG docker jenkins`), AWS CLI v2, kubectl, Helm; restart Jenkins.
3. Jenkins plugins: Git, Pipeline, Credentials Binding, GitHub.
4. Credentials: add a *Username with password* credential with id `aws-credentials` (AWS access key id / secret).
5. Create a *Pipeline* job -> "Pipeline script from SCM" -> your repo URL, branch `main`, script path `Jenkinsfile`. The `pollSCM('H/2 * * * *')` trigger starts a build on every new commit (or add a GitHub webhook to `<jenkins>/github-webhook/`).
6. Run *Build with Parameters* (`AWS_ACCOUNT_ID`, `AWS_REGION`, `EKS_CLUSTER`, `APP_URL`). The pipeline builds the five images, pushes them to ECR, runs `helm upgrade --install` and waits for every rollout.
7. Give the Jenkins EC2/IAM user permission on ECR and EKS and map it in the cluster (`eksctl create iamidentitymapping ...`) so `kubectl` works from the pipeline.

## 8. Monitoring and logging (CloudWatch)

```bash
# addon is created by eks/cluster.yaml; otherwise:
aws eks create-addon --cluster-name streamingapp-cluster --addon-name amazon-cloudwatch-observability
./scripts/cloudwatch-alarms.sh streamingapp-cluster ap-south-1 [sns-topic-arn]
```

Metrics: CloudWatch -> Container Insights -> EKS clusters. Logs: log groups `/aws/containerinsights/streamingapp-cluster/application`.

## 9. Scale, update, self-heal

```bash
kubectl scale deploy/streaming --replicas=4
kubectl get pods -l app=streaming

# rolling update (zero downtime: maxUnavailable 0, maxSurge 1)
helm upgrade streamingapp ./helm/streamingapp --reuse-values --set services.auth.tag=1.0.1
kubectl rollout status deploy/auth

# self-heal
kubectl delete pod -l app=chat --wait=false && kubectl get pods -w
```

## 10. Bonus - ChatOps

Create an SNS topic (`aws sns create-topic --name streamingapp-deploys`), publish from the Jenkins `post { success / failure }` blocks (`aws sns publish --topic-arn ... --message ...`), and subscribe Slack / Teams / Telegram through AWS Chatbot or a small Lambda webhook.

## 11. Teardown

```bash
helm uninstall streamingapp
eksctl delete cluster -f eks/cluster.yaml        # stop EKS charges
kind delete cluster --name streamingapp
```
