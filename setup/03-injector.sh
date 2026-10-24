#!/usr/bin/env bash
# Install only the Vault Agent Injector in GKE, pointed at the external Vault VM,
# plus a ServiceAccount that Vault uses to call the TokenReview API.
source "$(dirname "$0")/../lib.sh"

helm repo add hashicorp https://helm.releases.hashicorp.com >/dev/null 2>&1 || true
helm repo update hashicorp

# Pinned to the version tested for the talk.
helm upgrade --install vault hashicorp/vault --version 0.34.1 \
  --namespace vault --create-namespace \
  -f vault/values-injector.yaml \
  --set global.externalVaultAddr="http://$(state vault-ip):8200"

kubectl apply -f manifests/vault-auth.yaml
kubectl rollout status deployment/vault-agent-injector -n vault --timeout=180s
kubectl get pods -n vault
