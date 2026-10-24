#!/usr/bin/env bash
# Install the local tools the demo needs (macOS / Homebrew).
set -euo pipefail

brew install kubectl kubectx helm jq openssl
brew install --cask google-cloud-sdk

# Vault CLI comes from HashiCorp's own tap.
brew tap hashicorp/tap
brew install hashicorp/tap/vault

# GKE needs this plugin for kubectl to authenticate.
gcloud components install gke-gcloud-auth-plugin --quiet

echo
echo "Next: gcloud auth login  (opens a browser), then ./setup.sh"
