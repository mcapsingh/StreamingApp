#!/usr/bin/env bash
# Create CloudWatch alarms on EKS Container Insights metrics (requires the amazon-cloudwatch-observability addon).
# Usage: ./scripts/cloudwatch-alarms.sh <cluster-name> [region] [sns-topic-arn]
set -euo pipefail
CLUSTER="${1:?cluster name required}"
REGION="${2:-ap-south-1}"
SNS="${3:-}"
ACTIONS=()
[ -n "$SNS" ] && ACTIONS=(--alarm-actions "$SNS")

aws cloudwatch put-metric-alarm --region "$REGION" --alarm-name "${CLUSTER}-node-cpu-high" \
  --namespace ContainerInsights --metric-name node_cpu_utilization \
  --dimensions Name=ClusterName,Value="$CLUSTER" \
  --statistic Average --period 300 --evaluation-periods 2 --threshold 80 \
  --comparison-operator GreaterThanThreshold "${ACTIONS[@]}"

aws cloudwatch put-metric-alarm --region "$REGION" --alarm-name "${CLUSTER}-node-memory-high" \
  --namespace ContainerInsights --metric-name node_memory_utilization \
  --dimensions Name=ClusterName,Value="$CLUSTER" \
  --statistic Average --period 300 --evaluation-periods 2 --threshold 80 \
  --comparison-operator GreaterThanThreshold "${ACTIONS[@]}"

aws cloudwatch put-metric-alarm --region "$REGION" --alarm-name "${CLUSTER}-pod-restarts" \
  --namespace ContainerInsights --metric-name pod_number_of_container_restarts \
  --dimensions Name=ClusterName,Value="$CLUSTER" \
  --statistic Sum --period 300 --evaluation-periods 1 --threshold 3 \
  --comparison-operator GreaterThanThreshold "${ACTIONS[@]}"
echo "Alarms created for cluster $CLUSTER"
