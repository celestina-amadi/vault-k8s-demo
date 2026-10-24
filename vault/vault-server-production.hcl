# REFERENCE ONLY (not used in the demo).
# A starting point for Vault on Compute Engine VMs: 3 nodes (one per zone, e.g. a regional
# managed instance group), integrated Raft storage, TLS, and auto-unseal with Cloud KMS.
# Review every value before use.

ui            = true
disable_mlock = true

storage "raft" {
  path    = "/opt/vault/data"
  node_id = "vault-a"   # unique per node

  retry_join {
    auto_join        = "provider=gce project_name=YOUR_PROJECT tag_value=vault"
    auto_join_scheme = "https"
    leader_ca_cert_file = "/opt/vault/tls/ca.crt"
  }
}

listener "tcp" {
  address            = "0.0.0.0:8200"
  cluster_address    = "0.0.0.0:8201"
  tls_cert_file      = "/opt/vault/tls/vault.crt"
  tls_key_file       = "/opt/vault/tls/vault.key"
  tls_client_ca_file = "/opt/vault/tls/ca.crt"
}

# Auto-unseal: the VMs' service account needs roles/cloudkms.cryptoKeyEncrypterDecrypter on this key.
seal "gcpckms" {
  project    = "YOUR_PROJECT"
  region     = "global"
  key_ring   = "vault"
  crypto_key = "vault-unseal"
}

api_addr     = "https://vault.internal.example:8200"   # internal load balancer / DNS name
cluster_addr = "https://NODE_INTERNAL_IP:8201"

telemetry {
  prometheus_retention_time = "30s"
  disable_hostname          = true
}

# After first start: vault audit enable file file_path=/var/log/vault/audit.log
