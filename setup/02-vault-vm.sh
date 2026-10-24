#!/usr/bin/env bash
# Vault on a Compute Engine VM, outside the cluster, with no public IP. Reachable only from
# inside the VPC (GKE nodes and pods, the Envoy gateway) and through IAP from your laptop.
# It reaches the internet (to install Vault) through Cloud NAT.
source "$(dirname "$0")/../scripts/lib.sh"

POD_CIDR="$(gcloud container clusters describe "$CLUSTER_NAME" --zone "$ZONE" --format='value(clusterIpv4Cidr)')"
SUBNET_CIDR="$(gcloud compute networks subnets describe "$NETWORK" --region "$REGION" --format='value(ipCidrRange)')"

# Firewall: IAP for SSH and the tunnel, and port 8200 from GKE nodes and pods only.
gcloud compute firewall-rules describe vault-allow-iap >/dev/null 2>&1 || \
  gcloud compute firewall-rules create vault-allow-iap --network "$NETWORK" \
    --direction INGRESS --allow tcp:22,tcp:8200 \
    --source-ranges 35.235.240.0/20 --target-tags vault

gcloud compute firewall-rules describe vault-allow-gke >/dev/null 2>&1 || \
  gcloud compute firewall-rules create vault-allow-gke --network "$NETWORK" \
    --direction INGRESS --allow tcp:8200 \
    --source-ranges "$POD_CIDR,$SUBNET_CIDR" --target-tags vault

if ! gcloud compute instances describe "$VAULT_VM_NAME" --zone "$ZONE" >/dev/null 2>&1; then
  gcloud compute instances create "$VAULT_VM_NAME" \
    --zone "$ZONE" \
    --machine-type e2-small \
    --network "$NETWORK" \
    --no-address \
    --image-family debian-12 --image-project debian-cloud \
    --tags vault \
    --metadata-from-file startup-script=vault/vm-startup.sh
fi

gcloud compute instances describe "$VAULT_VM_NAME" --zone "$ZONE" \
  --format='value(networkInterfaces[0].networkIP)' > "$STATE/vault-ip"
echo "Vault VM internal IP: $(state vault-ip)"

# Temporary tunnel so this script can initialise Vault. A new VM can take a minute
# before IAP accepts connections, so restart the tunnel whenever it exits.
TUNNEL_PID=""
start_tunnel() {
  gcloud compute start-iap-tunnel "$VAULT_VM_NAME" 8200 \
    --local-host-port="localhost:${VAULT_LOCAL_PORT}" --zone "$ZONE" >/dev/null 2>&1 &
  TUNNEL_PID=$!
}
trap '[[ -n "$TUNNEL_PID" ]] && kill "$TUNNEL_PID" 2>/dev/null || true' EXIT

echo "Waiting for Vault to install and start on the VM (1-3 minutes)..."
rc=1
for _ in $(seq 1 60); do
  if [[ -z "$TUNNEL_PID" ]] || ! kill -0 "$TUNNEL_PID" 2>/dev/null; then start_tunnel; sleep 5; fi
  rc=0; vault status >/dev/null 2>&1 || rc=$?
  [[ $rc != 1 ]] && break
  sleep 5
done
if [[ $rc == 1 ]]; then
  echo "Vault did not become reachable through IAP. Check: ./scripts/tunnel.sh, and the VM's serial log." >&2
  exit 1
fi

if [[ ! -s "$STATE/vault-init.json" ]]; then
  # One key share keeps the demo simple. Production: auto-unseal with Cloud KMS.
  (umask 077; vault operator init -key-shares=1 -key-threshold=1 -format=json > "$STATE/vault-init.json.tmp")
  mv "$STATE/vault-init.json.tmp" "$STATE/vault-init.json"
fi

rc=0; vault status >/dev/null 2>&1 || rc=$?
if [[ $rc == 2 ]]; then
  vault operator unseal "$(jq -r '.unseal_keys_b64[0]' "$STATE/vault-init.json")" >/dev/null
fi
vault status
