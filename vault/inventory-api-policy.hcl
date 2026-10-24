# inventory-api may read its own prod config, and nothing else.
path "secret/data/inventory-api/prod/*" {
  capabilities = ["read"]
}
