#!/usr/bin/env bash
# Network egress (Cloud NAT) and a private GKE Standard cluster: nodes have no public IPs.
# kubectl uses the DNS endpoint (IAM-authenticated); the public IP endpoint accepts nobody.
source "$(dirname "$0")/../scripts/lib.sh"

if [[ "$PROJECT_ID" == "your-gcp-project-id" ]]; then
  echo "Set PROJECT_ID in config.env first." >&2
  exit 1
fi

gcloud config set project "$PROJECT_ID"
gcloud services enable container.googleapis.com compute.googleapis.com iap.googleapis.com

# Cloud NAT: private nodes and the Vault VM have no public IPs, but still need to pull
# images and packages. Outbound only; nothing can connect in through it.
gcloud compute routers describe vault-demo-router --region "$REGION" >/dev/null 2>&1 || \
  gcloud compute routers create vault-demo-router --network "$NETWORK" --region "$REGION"
gcloud compute routers nats describe vault-demo-nat --router vault-demo-router --region "$REGION" >/dev/null 2>&1 || \
  gcloud compute routers nats create vault-demo-nat --router vault-demo-router --region "$REGION" \
    --auto-allocate-nat-external-ips --nat-all-subnet-ip-ranges

SUBNET_CIDR="$(gcloud compute networks subnets describe "$NETWORK" --region "$REGION" --format='value(ipCidrRange)')"

if ! gcloud container clusters describe "$CLUSTER_NAME" --zone "$ZONE" >/dev/null 2>&1; then
  # --enable-dns-access: kubectl reaches the control plane through a DNS endpoint that checks
  #   your Google identity (IAM), so it works from any network.
  # --master-authorized-networks: the IP endpoints only accept the VPC subnet (nodes, Vault VM).
  # --gateway-api=disabled: Envoy Gateway installs and manages the Gateway API CRDs itself.
  gcloud container clusters create "$CLUSTER_NAME" \
    --zone "$ZONE" \
    --num-nodes 2 \
    --machine-type e2-standard-4 \
    --release-channel regular \
    --enable-ip-alias \
    --enable-private-nodes \
    --enable-dns-access \
    --enable-master-authorized-networks \
    --master-authorized-networks "$SUBNET_CIDR" \
    --gateway-api=disabled \
    --workload-pool "$PROJECT_ID.svc.id.goog"
fi

gcloud container clusters get-credentials "$CLUSTER_NAME" --zone "$ZONE" --dns-endpoint

# Vault (on a VM with no public IP) calls the control plane's private endpoint for TokenReview.
# The VM is in $SUBNET_CIDR, which the authorized networks above allow.
PRIVATE_ENDPOINT="$(gcloud container clusters describe "$CLUSTER_NAME" --zone "$ZONE" \
  --format='value(privateClusterConfig.privateEndpoint)')"
echo "$PRIVATE_ENDPOINT" > "$STATE/gke-private-endpoint"
echo "Control plane private endpoint: $PRIVATE_ENDPOINT"

# The injector webhook listens on 8080. On this cluster type the control plane reaches nodes
# from inside the VPC, which GKE's own "-vms" firewall rule already allows on all ports.

# Short context name for readable kubectx output.
kubectx vault-demo="$(kubectl config current-context)" 2>/dev/null || true
kubectl get nodes -o wide
