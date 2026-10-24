#!/usr/bin/env bash
# ACT 3 (bonus) — Dynamic MySQL credentials on Cloud SQL (~5 min)
# Needs act2 to have run first (it enables KV and Kubernetes auth).
source "$(dirname "$0")/lib.sh"
require_vault

SQL_IP="$(state sql-ip)"
VAULT_ADMIN_PW="$(state mysql-vault-password)"

say "1. Enable the database secrets engine and connect it to Cloud SQL (private IP)"
step v secrets enable database
step 'v write database/config/orders-db \
  plugin_name=mysql-database-plugin \
  allowed_roles=orders-api \
  connection_url="{{username}}:{{password}}@tcp(${SQL_IP}:3306)/" \
  username=vault_admin password="$VAULT_ADMIN_PW"'

say "2. Rotate vault_admin's password. Now only Vault knows it."
step v write -f database/rotate-root/orders-db

say "3. A role: what SQL creates a user, what SQL removes it, and how long it lives"
step cat vault/orders-api-creation.sql vault/orders-api-revocation.sql
step v write database/roles/orders-api db_name=orders-db \
  creation_statements=@vault/orders-api-creation.sql \
  revocation_statements=@vault/orders-api-revocation.sql \
  default_ttl=2m max_ttl=10m

say "4. Ask for credentials. Every read creates a brand new MySQL user."
step v read database/creds/orders-api
step "mysql_admin -e \"SELECT user, host FROM mysql.user WHERE user LIKE 'v-%'\""

say "5. Wire it to a workload: endpoint in KV, policy, Kubernetes role, annotations"
step 'v kv put secret/orders-api/prod/database host="$SQL_IP" port=3306 name=orders'
step v policy write orders-api vault/orders-api-policy.hcl
step v write auth/kubernetes/role/orders-api \
  bound_service_account_names=orders-api \
  bound_service_account_namespaces=orders \
  policies=orders-api ttl=1h
step kubectl apply -f manifests/act3-orders-api.yaml
step kubectl rollout status deployment/orders-api -n orders --timeout=120s
step kubectl logs -n orders deploy/orders-api -c app --tail=3

say "6. Incident! Revoke every credential this role ever issued, in one command"
step v lease revoke -prefix database/creds/orders-api
sleep 5   # revocation is queued; give Vault a moment to drop the users
step "mysql_admin -e \"SELECT user, host FROM mysql.user WHERE user LIKE 'v-%'\""
echo "(waiting 15s...)"; sleep 15
step kubectl logs -n orders deploy/orders-api -c app --tail=3

say "Recovery: restart the pod, and it gets a new user (or wait for the agent to re-fetch)"
step kubectl rollout restart deployment/orders-api -n orders
step kubectl rollout status deployment/orders-api -n orders --timeout=120s
# The old pod lingers while it terminates; wait so the logs come from the new one.
echo "(waiting for the old pod to stop...)"
while (( $(kubectl get pods -n orders -l app=orders-api --no-headers 2>/dev/null | wc -l) > 1 )); do sleep 2; done
step kubectl logs -n orders deploy/orders-api -c app --tail=2
