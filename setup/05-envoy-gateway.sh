#!/usr/bin/env bash
# Envoy Gateway in GKE, exposing the Vault UI (running on the private VM) to your browser.
# HTTPS with a self-signed certificate, and only from the IP ranges in VAULT_UI_ALLOWED_CIDRS.
source "$(dirname "$0")/../scripts/lib.sh"

helm upgrade --install eg oci://docker.io/envoyproxy/gateway-helm \
  --version "$ENVOY_GATEWAY_VERSION" \
  --namespace envoy-gateway-system --create-namespace
kubectl wait --for=condition=Available deployment/envoy-gateway -n envoy-gateway-system --timeout=180s

# Who may reach the UI. Default: the public IP you're on right now.
ALLOWED="${VAULT_UI_ALLOWED_CIDRS:-$(curl -s https://api.ipify.org)/32}"
echo "Vault UI will accept connections from: $ALLOWED"

# Self-signed certificate (the browser will warn once). Production: cert-manager + a real domain.
if [[ ! -s "$STATE/vault-ui.key" ]]; then
  (umask 077; openssl req -x509 -nodes -newkey rsa:2048 -days 30 \
    -keyout "$STATE/vault-ui.key" -out "$STATE/vault-ui.crt" -subj "/CN=vault-ui.demo" 2>/dev/null)
fi
kubectl create secret tls vault-ui-tls -n vault \
  --cert="$STATE/vault-ui.crt" --key="$STATE/vault-ui.key" \
  --dry-run=client -o yaml | kubectl apply -f -

CIDRS_YAML="$(echo "$ALLOWED" | tr ',' '\n' | sed 's/.*/"&"/' | paste -sd, -)"
sed -e "s|__VAULT_IP__|$(state vault-ip)|" -e "s|__ALLOWED_CIDRS__|$CIDRS_YAML|" \
  manifests/vault-ui-gateway.yaml | kubectl apply -f -

echo "Waiting for the load balancer IP..."
ADDR=""
for _ in $(seq 1 60); do
  ADDR="$(kubectl get gateway vault-ui -n vault -o jsonpath='{.status.addresses[0].value}' 2>/dev/null || true)"
  [[ -n "$ADDR" ]] && break
  sleep 5
done
echo "$ADDR" > "$STATE/vault-ui-ip"
echo
echo "Vault UI: https://$ADDR/ui   (accept the self-signed certificate warning)"
echo "Sign in with the token from: jq -r .root_token .state/vault-init.json"
