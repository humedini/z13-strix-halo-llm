#!/bin/bash
# Publishes the Lemonade web UI + API to the tailnet.
#
# No nginx shim needed here: unlike Ollama, Lemonade accepts any Host header,
# so tailscale serve can proxy it directly. Lemonade stays bound to loopback;
# Tailscale remains the only ingress.
set -euo pipefail

PORT=13305
TSNAME=$(tailscale status --json | grep -oP '"DNSName":\s*"\K[^"]+' | head -1 | sed 's/\.$//')
[[ -n "$TSNAME" ]] || { echo "Not connected to a tailnet"; exit 1; }

echo "==> Publishing Lemonade on https://${TSNAME}:${PORT}"
tailscale serve --bg --https=${PORT} "http://127.0.0.1:${PORT}"

echo
echo "==> All tailnet routes now:"
tailscale serve status | sed 's/^/    /'

echo
echo "==> Verification"
echo -n "  local  : "; curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:${PORT}/"
echo -n "  tailnet: "; curl -s -o /dev/null -m 20 -w "%{http_code}\n" "https://${TSNAME}:${PORT}/"

echo
echo "  Web UI:  https://${TSNAME}:${PORT}"
echo "  API:     https://${TSNAME}:${PORT}/api/v1"
echo
echo "  NOTE: Lemonade has no authentication by default, so anything on your"
echo "  tailnet can use it. That is your own devices only, but unlike Open WebUI"
echo "  there is no login. Set one with:  lemonade config set api_key <key>"
