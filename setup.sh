#!/usr/bin/env bash
# One-shot setup, mirroring production: private GKE + Vault on a private VM + MySQL on Cloud SQL,
# with the Vault UI served through Envoy Gateway.
# Run it at least a day before the talk (Cloud SQL alone takes 5-10 minutes).
set -euo pipefail
cd "$(dirname "$0")"

for tool in gcloud kubectl helm vault jq openssl curl; do
  command -v "$tool" >/dev/null || { echo "Missing $tool. Run setup/00-tools.sh" >&2; exit 1; }
done

./setup/01-gke-cluster.sh
./setup/02-vault-vm.sh
./setup/03-injector.sh
./setup/04-cloudsql-mysql.sh
./setup/05-envoy-gateway.sh

echo
echo "Ready. In another tab: ./tunnel.sh"
echo "Then rehearse: AUTO=1 ./act1-base64.sh && AUTO=1 ./act2-vault-kv-injector.sh && AUTO=1 ./act3-dynamic-db.sh"
