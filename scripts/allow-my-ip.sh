#!/usr/bin/env bash
# Let the network you are on now reach the Vault UI.
# Usage: ./scripts/allow-my-ip.sh            -> your current public IP only
#        ./scripts/allow-my-ip.sh 1.2.3.4/32,5.6.7.0/24
source "$(dirname "$0")/lib.sh"

ALLOWED="${1:-$(curl -s https://api.ipify.org)/32}"
CIDRS_JSON="$(echo "$ALLOWED" | tr ',' '\n' | sed 's/.*/"&"/' | paste -sd, -)"

kubectl patch envoyproxy vault-ui-proxy -n envoy-gateway-system --type merge \
  -p "{\"spec\":{\"provider\":{\"kubernetes\":{\"envoyService\":{\"loadBalancerSourceRanges\":[${CIDRS_JSON}]}}}}}"
echo "Vault UI now accepts: $ALLOWED (takes up to a minute to apply)"
echo "URL: https://$(state vault-ui-ip)/ui"
