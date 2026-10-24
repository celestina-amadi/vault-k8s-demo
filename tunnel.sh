#!/usr/bin/env bash
# Keep this running in its own terminal tab: forwards localhost:8200 to the Vault VM through IAP.
# Vault's port is never exposed to the internet.
set -euo pipefail
source "$(dirname "$0")/config.env"

exec gcloud compute start-iap-tunnel "$VAULT_VM_NAME" 8200 \
  --local-host-port="localhost:${VAULT_LOCAL_PORT}" \
  --zone "$ZONE" --project "$PROJECT_ID"
