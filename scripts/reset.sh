#!/usr/bin/env bash
# Remove everything the acts created, so the walkthrough can run again from the start.
# Needs ./scripts/tunnel.sh running in another tab.
source "$(dirname "$0")/lib.sh"
require_vault

kubectl delete namespace demo-insecure inventory orders --ignore-not-found --wait=true

# Vault: disabling the database engine revokes its leases, which drops the MySQL users it created.
vault secrets disable database   || true
vault secrets disable secret     || true
vault auth disable kubernetes    || true
vault policy delete inventory-api || true
vault policy delete orders-api   || true

# MySQL: Act 3 rotated vault_admin's password, so set it back. Then drop any leftover Vault users.
gcloud sql users set-password vault_admin --host=% --instance="$SQL_INSTANCE" \
  --password="$(state mysql-vault-password)"
mysql_admin -N -e "SELECT CONCAT('DROP USER \`', user, '\`@\`', host, '\`;') FROM mysql.user WHERE user LIKE 'v-%'" \
  | mysql_admin

echo "Reset complete."
