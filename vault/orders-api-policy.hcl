# orders-api may read its connection details and request short-lived MySQL credentials. Nothing else.
path "secret/data/orders-api/prod/*" {
  capabilities = ["read"]
}

path "database/creds/orders-api" {
  capabilities = ["read"]
}
