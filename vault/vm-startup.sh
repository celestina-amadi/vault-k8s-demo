#!/bin/bash
# Compute Engine startup script for the Vault VM (runs as root on every boot).
# Single node, integrated Raft storage, plain HTTP inside the VPC. Demo only:
# see vault/vault-server-production.hcl for TLS, HA and auto-unseal.
set -euo pipefail

if ! command -v vault >/dev/null; then
  apt-get update
  apt-get install -y gpg curl lsb-release
  curl -fsSL https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
    > /etc/apt/sources.list.d/hashicorp.list
  apt-get update
  apt-get install -y vault
fi

IP="$(curl -s -H 'Metadata-Flavor: Google' \
  http://metadata.google.internal/computeMetadata/v1/instance/network-interfaces/0/ip)"

cat > /etc/vault.d/vault.hcl <<EOF
ui            = true
disable_mlock = true

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-1"
}

listener "tcp" {
  address     = "0.0.0.0:8200"
  tls_disable = true
}

api_addr     = "http://${IP}:8200"
cluster_addr = "http://${IP}:8201"
EOF

mkdir -p /opt/vault/data
chown -R vault:vault /opt/vault
systemctl enable vault
systemctl restart vault
