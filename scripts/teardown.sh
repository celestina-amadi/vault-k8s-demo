#!/usr/bin/env bash
# Delete everything setup created, so it stops costing money.
# Each step carries on if the resource is already gone. Override ZONE to clean up another zone:
#   ZONE=us-central1-a ./scripts/teardown.sh
cd "$(dirname "$0")/.."
source config.env
REGION="${ZONE%-*}"

# Delete the gateway first, so Kubernetes removes the load balancer it created.
kubectl delete gateway vault-ui -n vault --ignore-not-found --timeout=120s 2>/dev/null || true
kubectl delete svc -n envoy-gateway-system -l gateway.envoyproxy.io/owning-gateway-name=vault-ui \
  --ignore-not-found --timeout=120s 2>/dev/null || true

gcloud container clusters delete "$CLUSTER_NAME" --zone "$ZONE" --project "$PROJECT_ID" --quiet || true
gcloud compute instances delete "$VAULT_VM_NAME" --zone "$ZONE" --project "$PROJECT_ID" --quiet || true
gcloud sql instances delete "$SQL_INSTANCE" --project "$PROJECT_ID" --quiet || true
gcloud compute firewall-rules delete vault-allow-iap vault-allow-gke gke-allow-vault-injector \
  --project "$PROJECT_ID" --quiet || true
gcloud compute routers delete vault-demo-router --region "$REGION" --project "$PROJECT_ID" --quiet || true

# The VPC peering for Cloud SQL private IP is left in place (free, and reused if you set up again).
rm -rf .state
echo "Teardown complete."
