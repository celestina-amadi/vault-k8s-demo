#!/usr/bin/env bash
# Unseal Vault after the VM restarts. (Production would use Cloud KMS auto-unseal instead.)
source "$(dirname "$0")/lib.sh"

rc=0; vault status >/dev/null 2>&1 || rc=$?
if [[ $rc == 1 ]]; then echo "Can't reach Vault. Is ./scripts/tunnel.sh running?" >&2; exit 1; fi
if [[ $rc == 0 ]]; then echo "Vault is already unsealed."; exit 0; fi

vault operator unseal "$(jq -r '.unseal_keys_b64[0]' "$STATE/vault-init.json")" >/dev/null
vault status
