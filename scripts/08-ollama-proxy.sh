#!/bin/bash
# Fixes the 403 from Ollama when reached via `tailscale serve`.
#
# Ollama validates the Host header and only accepts localhost/127.0.0.1 as a
# DNS-rebinding guard. Tailscale Serve forwards the .ts.net hostname, so Ollama
# returns 403. OLLAMA_ORIGINS does not help: it governs the Origin header (CORS),
# not Host.
#
# Rather than set OLLAMA_HOST=0.0.0.0 (which would expose the unauthenticated API
# to every network you join), we put a loopback-only nginx shim in front that
# rewrites Host, and point tailscale serve at that. Ollama stays on 127.0.0.1.
set -euo pipefail

SHIM_PORT=11435
OLLAMA_PORT=11434
TSNAME=$(tailscale status --json | grep -oP '"DNSName":\s*"\K[^"]+' | head -1 | sed 's/\.$//')

echo "==> Installing nginx"
apt-get install -y nginx

# nginx ships a default site on 0.0.0.0:80 — remove it; we are not serving :80.
if [[ -e /etc/nginx/sites-enabled/default ]]; then
    rm -f /etc/nginx/sites-enabled/default
    echo "==> Removed nginx default site (it listened on 0.0.0.0:80)"
fi

echo "==> Writing the Host-rewriting shim"
cat > /etc/nginx/sites-available/ollama-shim << NGINX
# Loopback-only shim: rewrites Host so Ollama accepts proxied requests.
server {
    listen 127.0.0.1:${SHIM_PORT};
    server_name _;

    # No client_max_body_size limit: model pushes can be large.
    client_max_body_size 0;

    location / {
        proxy_pass http://127.0.0.1:${OLLAMA_PORT};

        # The actual fix.
        proxy_set_header Host 127.0.0.1:${OLLAMA_PORT};

        proxy_http_version 1.1;
        proxy_set_header Connection "";

        # Token streaming must not be buffered.
        proxy_buffering off;
        proxy_cache off;
        chunked_transfer_encoding on;

        # Long generations must not time out.
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
    }
}
NGINX

ln -sf /etc/nginx/sites-available/ollama-shim /etc/nginx/sites-enabled/ollama-shim

echo "==> Testing nginx config"
nginx -t

systemctl restart nginx
systemctl enable nginx >/dev/null 2>&1 || true

echo "==> Repointing tailscale serve at the shim"
tailscale serve --bg --https=${OLLAMA_PORT} "http://127.0.0.1:${SHIM_PORT}"

echo
echo "==> Verification"
echo -n "  shim direct (expect 200): "
curl -s -o /dev/null -w "%{http_code}\n" "http://127.0.0.1:${SHIM_PORT}/api/tags"
echo -n "  over tailnet (expect 200): "
curl -s -o /dev/null -w "%{http_code}\n" "https://${TSNAME}:${OLLAMA_PORT}/api/tags"
echo
echo "  Listening sockets (nothing should be 0.0.0.0):"
ss -tlnp 2>/dev/null | grep -E ":80 |:${SHIM_PORT}|:${OLLAMA_PORT}|:3000" | sed 's/^/    /'
