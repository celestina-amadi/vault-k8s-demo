#!/usr/bin/env bash
# ACT 2 — Vault KV + Kubernetes auth + Agent Injector into tmpfs (~10 min)
source "$(dirname "$0")/../scripts/lib.sh"
require_vault

say "Vault runs on a VM outside the cluster. Only the Agent Injector runs in GKE."
step v status
step kubectl get pods -n vault

# ---------------------------------------------------------------- KV
say "1. Enable KV v2 and store config, one path per concern: <app>/<env>/<kind>"
step v secrets enable -path=secret kv-v2
step v kv put secret/inventory-api/prod/database host=inventory-db.prod.internal port=5432 username=inventory password=SuperS3cret-Prod-Pass!
step v kv put secret/inventory-api/prod/third-party shipping_provider_key=sk_live_demo_4f9a8b7c6d5e email_api_key=em_demo_1a2b3c4d
step v kv put secret/inventory-api/prod/endpoints ledger_url=https://ledger.prod.internal fraud_check_url=https://fraud.prod.internal/v2/check
step v kv list secret/inventory-api/prod

# ---------------------------------------------------------------- Policy
say "2. A policy: inventory-api can read its own prod config, nothing else"
step cat vault/inventory-api-policy.hcl
step v policy write inventory-api vault/inventory-api-policy.hcl

# ---------------------------------------------------------------- Auth
say "3. Let Vault verify Kubernetes ServiceAccount tokens, using the GKE API"
REVIEWER_JWT="$(kubectl get secret vault-auth-token -n vault -o jsonpath='{.data.token}' | base64 -d)"
KUBE_HOST="https://$(state gke-private-endpoint)"   # the VM has no public IP: use the private endpoint
# The cluster CA (kubeconfig uses the DNS endpoint, so it doesn't carry this CA).
gcloud container clusters describe "$CLUSTER_NAME" --zone "$ZONE" \
  --format='value(masterAuth.clusterCaCertificate)' | base64 -d > "$STATE/gke-ca.crt"
step v auth enable kubernetes
step 'v write auth/kubernetes/config kubernetes_host="$KUBE_HOST" kubernetes_ca_cert=@"$STATE/gke-ca.crt" token_reviewer_jwt="$REVIEWER_JWT"'

say "4. Bind identity to policy: SA inventory-api in namespace inventory -> policy inventory-api"
step v write auth/kubernetes/role/inventory-api \
  bound_service_account_names=inventory-api \
  bound_service_account_namespaces=inventory \
  policies=inventory-api ttl=1h

# ---------------------------------------------------------------- Deploy
say "5. The app: plain Deployment + annotations. No Secret objects, no Vault SDK"
step "grep -n 'vault.hashicorp.com' manifests/act2-inventory-api.yaml | head -8"
step kubectl apply -f manifests/act2-inventory-api.yaml
step kubectl rollout status deployment/inventory-api -n inventory --timeout=120s

say "The injector added an init container and a sidecar"
step "kubectl get pod -n inventory -l app=inventory-api -o jsonpath='{range .items[0].spec.initContainers[*]}init: {.name}{\"\\n\"}{end}{range .items[0].spec.containers[*]}container: {.name}{\"\\n\"}{end}'"

say "6. Where did the secrets land?"
step kubectl exec -n inventory deploy/inventory-api -c app -- ls -l /vault/secrets
step kubectl exec -n inventory deploy/inventory-api -c app -- cat /vault/secrets/database.env
step kubectl exec -n inventory deploy/inventory-api -c app -- df -h /vault/secrets

say "tmpfs = RAM. And nothing in cluster state:"
step kubectl get secrets -n inventory

step kubectl logs -n inventory deploy/inventory-api -c app --tail=3

# ---------------------------------------------------------------- Denied
say "7. Same namespace, same role annotation, different ServiceAccount"
step kubectl apply -f manifests/act2-intruder.yaml
echo "(waiting 20s for the init container to try...)"; sleep 20
step kubectl get pods -n inventory -l app=intruder
step "kubectl logs -n inventory -l app=intruder -c vault-agent-init --tail=40 | awk '/Code: 403|not authorized/ && n++ < 2'"

# ---------------------------------------------------------------- Rotate
say "8. Rotate a key in Vault. No redeploy."
step v kv patch secret/inventory-api/prod/third-party shipping_provider_key=sk_rotated_9z8y7x6w5v4u
echo "(waiting 30s for the agent to re-render...)"; sleep 30
step kubectl exec -n inventory deploy/inventory-api -c app -- cat /vault/secrets/third-party.env
