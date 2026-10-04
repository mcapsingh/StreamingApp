#!/usr/bin/env bash
# Build (and optionally push) the five StreamingApp images.
#
#   ./scripts/build-push.sh <registry-prefix> [tag] [--push]
#
#   Docker Hub : ./scripts/build-push.sh mcapsingh 1.0.0 --push
#   Amazon ECR : ./scripts/build-push.sh 123456789012.dkr.ecr.ap-south-1.amazonaws.com 1.0.0 --push
#
# APP_URL is baked into the React bundle at build time (default: http://streamingapp.local).
set -euo pipefail

PREFIX="${1:?usage: build-push.sh <registry-prefix> [tag] [--push]}"
TAG="${2:-1.0.0}"
PUSH="${3:-}"
APP_URL="${APP_URL:-http://streamingapp.local}"

cd "$(dirname "$0")/.."

echo ">> building images as ${PREFIX}/streaming-<svc>:${TAG}"
docker build -t "${PREFIX}/streaming-auth:${TAG}" backend/authService
docker build -t "${PREFIX}/streaming-stream:${TAG}" -f backend/streamingService/Dockerfile backend
docker build -t "${PREFIX}/streaming-admin:${TAG}" -f backend/adminService/Dockerfile backend
docker build -t "${PREFIX}/streaming-chat:${TAG}" -f backend/chatService/Dockerfile backend
docker build -t "${PREFIX}/streaming-frontend:${TAG}" \
  --build-arg REACT_APP_AUTH_API_URL="${APP_URL}/api/auth" \
  --build-arg REACT_APP_STREAMING_API_URL="${APP_URL}/api/streaming" \
  --build-arg REACT_APP_STREAMING_PUBLIC_URL="${APP_URL}" \
  --build-arg REACT_APP_ADMIN_API_URL="${APP_URL}/api/admin" \
  --build-arg REACT_APP_CHAT_API_URL="${APP_URL}/api/chat" \
  --build-arg REACT_APP_CHAT_SOCKET_URL="${APP_URL}" \
  frontend

if [ "${PUSH}" = "--push" ]; then
  for svc in auth stream admin chat frontend; do
    docker push "${PREFIX}/streaming-${svc}:${TAG}"
  done
fi
