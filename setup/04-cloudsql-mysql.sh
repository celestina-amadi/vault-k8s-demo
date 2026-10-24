#!/usr/bin/env bash
# MySQL 8.0 on Cloud SQL with a private IP only, for the dynamic-credentials demo.
source "$(dirname "$0")/../lib.sh"

gcloud services enable sqladmin.googleapis.com servicenetworking.googleapis.com

# Private services access: lets the VPC (GKE pods, the Vault VM) reach Cloud SQL privately. Once per VPC.
RANGE="google-managed-services-${NETWORK}"
gcloud compute addresses describe "$RANGE" --global >/dev/null 2>&1 || \
  gcloud compute addresses create "$RANGE" --global --purpose=VPC_PEERING \
    --prefix-length=16 --network="$NETWORK"
gcloud services vpc-peerings connect --service=servicenetworking.googleapis.com \
  --ranges="$RANGE" --network="$NETWORK" 2>/dev/null || echo "(VPC peering already exists)"

if ! gcloud sql instances describe "$SQL_INSTANCE" >/dev/null 2>&1; then
  echo "Creating Cloud SQL instance (5-10 minutes)..."
  # ALLOW_UNENCRYPTED_AND_ENCRYPTED keeps the demo simple. Production: require TLS.
  gcloud sql instances create "$SQL_INSTANCE" \
    --database-version=MYSQL_8_0 --edition=enterprise --tier=db-f1-micro \
    --region="$REGION" --network="$NETWORK" --no-assign-ip \
    --ssl-mode=ALLOW_UNENCRYPTED_AND_ENCRYPTED
fi

gcloud sql instances describe "$SQL_INSTANCE" --format=json \
  | jq -r '.ipAddresses[] | select(.type=="PRIVATE") | .ipAddress' > "$STATE/sql-ip"
echo "Cloud SQL private IP: $(state sql-ip)"

[[ -s "$STATE/mysql-root-password" ]]  || openssl rand -hex 16 > "$STATE/mysql-root-password"
[[ -s "$STATE/mysql-vault-password" ]] || openssl rand -hex 16 > "$STATE/mysql-vault-password"
chmod 600 "$STATE"/mysql-*-password

gcloud sql users set-password root --host=% --instance="$SQL_INSTANCE" \
  --password="$(state mysql-root-password)"

# The account Vault uses to create and drop users. Act 3 rotates its password so only Vault knows it.
if gcloud sql users list --instance="$SQL_INSTANCE" --format='value(name)' | grep -qx vault_admin; then
  gcloud sql users set-password vault_admin --host=% --instance="$SQL_INSTANCE" \
    --password="$(state mysql-vault-password)"
else
  gcloud sql users create vault_admin --host=% --instance="$SQL_INSTANCE" \
    --password="$(state mysql-vault-password)"
fi

gcloud sql databases describe orders --instance="$SQL_INSTANCE" >/dev/null 2>&1 || \
  gcloud sql databases create orders --instance="$SQL_INSTANCE"

# A client pod inside the cluster for admin queries (Cloud SQL has no public IP).
kubectl apply -f manifests/mysql-client.yaml
kubectl wait --for=condition=Ready pod/mysql-client -n db --timeout=180s
mysql_admin orders < vault/orders-schema.sql
echo "Cloud SQL ready."
