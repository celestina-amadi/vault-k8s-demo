#!/usr/bin/env bash
# ACT 1 — The Base64 reality check (~3 min)
source "$(dirname "$0")/../scripts/lib.sh"

say "A perfectly normal Kubernetes Secret, the kind that lives in Git"
step cat manifests/act1-k8s-secret.yaml
step kubectl apply -f manifests/act1-k8s-secret.yaml

say "What the API server hands back to anyone allowed to 'get secrets'"
step kubectl get secret inventory-db -n demo-insecure -o yaml

say "Base64 is encoding, not encryption"
step "kubectl get secret inventory-db -n demo-insecure -o jsonpath='{.data.password}' | base64 -d; echo"

say "Every key, decoded, in one line"
step "kubectl get secret inventory-db -n demo-insecure -o json | jq -r '.data | map_values(@base64d)'"

say "Who can do that? Give a developer the common built-in 'edit' role..."
step kubectl create rolebinding dev-edit --clusterrole=edit --user=dev@example.com -n demo-insecure
step kubectl auth can-i get secrets -n demo-insecure --as=dev@example.com

say "...and anyone who can create a pod can mount any secret in the namespace"
step kubectl auth can-i create pods -n demo-insecure --as=dev@example.com
