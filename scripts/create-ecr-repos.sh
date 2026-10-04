#!/usr/bin/env bash
# Create one ECR repository per component. Usage: ./scripts/create-ecr-repos.sh [region]
set -euo pipefail
REGION="${1:-ap-south-1}"
for svc in auth stream admin chat frontend; do
  aws ecr describe-repositories --repository-names "streaming-${svc}" --region "$REGION" >/dev/null 2>&1 \
    || aws ecr create-repository --repository-name "streaming-${svc}" --region "$REGION" \
         --image-scanning-configuration scanOnPush=true >/dev/null
  echo "ECR repo ready: streaming-${svc}"
done
