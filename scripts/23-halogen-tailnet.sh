#!/bin/bash
# Publishes halogen-flash-server (port 8731) to the tailnet.
# Halogen binds 127.0.0.1:8731 via the compose file; tailscale serve is the only
# ingress, matching every other service on this machine.
set -euo pipefail
PORT=8731
TSNAME=$(tailscale status --json | grep -oP '"DNSName":\s*"\K[^"]+' | head -1 | sed 's/\.$//')
[[ -n "$TSNAME" ]] || { echo "Not connected to a tailnet"; exit 1; }
# Check Host-header handling first: if it 403s like Ollama, it needs the nginx shim.
code=$(curl -s -o /dev/null -m 10 -H "Host: ${TSNAME}:${PORT}" "http://127.0.0.1:${PORT}/health" || true)
echo "==> Halogen with a tailnet Host header -> HTTP ${code}"
if [[ "$code" == "403" ]]; then
    echo "  Halogen rejects foreign Host headers; needs a shim like 08-ollama-proxy.sh. Not publishing."
    exit 1
fi
tailscale serve --bg --https=${PORT} "http://127.0.0.1:${PORT}"
echo; tailscale serve status | sed 's/^/    /'
echo; echo -n "  tailnet: "; curl -s -o /dev/null -m 20 -w "%{http_code}\n" "https://${TSNAME}:${PORT}/health"
echo "  API: https://${TSNAME}:${PORT}/v1"
