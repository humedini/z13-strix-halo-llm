#!/bin/bash
# 1. Rebinds Open WebUI off 0.0.0.0 and onto the host loopback, which also
#    restores its ability to reach Ollama (now on 127.0.0.1, unreachable via
#    the docker bridge / host.docker.internal).
# 2. Publishes Open WebUI + the Ollama API to the tailnet via `tailscale serve`.
#
# Data is preserved: the named volume "open-webui" is untouched by recreation.
set -uo pipefail

WEBUI_PORT=3000
OLLAMA_PORT=11434

echo "############ PRE-FLIGHT ############"
if ! tailscale status >/dev/null 2>&1; then
    echo "ERROR: not connected to a tailnet. Run 'sudo tailscale up' first."
    exit 1
fi
TSNAME=$(tailscale status --json | grep -oP '"DNSName":\s*"\K[^"]+' | head -1 | sed 's/\.$//')
echo "  tailnet name: ${TSNAME:-unknown}"
echo "  current bindings:"; ss -tlnp 2>/dev/null | grep -E ":${WEBUI_PORT}|:${OLLAMA_PORT}" | sed 's/^/    /'
echo "####################################"
echo

# ---------- 1. Open WebUI -> host network, loopback only ----------
if docker ps -a --format '{{.Names}}' | grep -q '^open-webui$'; then
    echo "==> Recreating open-webui bound to loopback (volume preserved)"
    docker rm -f open-webui >/dev/null 2>&1 || true
    docker run -d \
        --name open-webui \
        --restart always \
        --network=host \
        -e HOST=127.0.0.1 \
        -e PORT=${WEBUI_PORT} \
        -e OLLAMA_BASE_URL=http://127.0.0.1:${OLLAMA_PORT} \
        -v open-webui:/app/backend/data \
        ghcr.io/open-webui/open-webui:main

    echo "==> Waiting for it to bind..."
    for i in $(seq 1 30); do
        sleep 2
        if ss -tln 2>/dev/null | grep -q "127.0.0.1:${WEBUI_PORT}"; then
            echo "    bound to 127.0.0.1:${WEBUI_PORT}  ✓"; break
        fi
        if ss -tln 2>/dev/null | grep -qE "0\.0\.0\.0:${WEBUI_PORT}|\*:${WEBUI_PORT}"; then
            echo "    WARNING: bound to 0.0.0.0 — the image ignored HOST."
            echo "    Falling back to a published-port container instead."
            docker rm -f open-webui >/dev/null 2>&1 || true
            docker run -d --name open-webui --restart always \
                -p 127.0.0.1:${WEBUI_PORT}:8080 \
                --add-host=host.docker.internal:host-gateway \
                -e OLLAMA_BASE_URL=http://host.docker.internal:${OLLAMA_PORT} \
                -v open-webui:/app/backend/data \
                ghcr.io/open-webui/open-webui:main
            echo "    NOTE: in this fallback Ollama must be reachable on the docker"
            echo "          bridge; see the summary at the end."
            break
        fi
    done
else
    echo "==> No open-webui container found; skipping."
fi

# ---------- 1b. Allow the tailnet origin through Ollama's CORS check ----------
# Default OLLAMA_ORIGINS covers only localhost/127.0.0.1/0.0.0.0, so browser
# clients reaching the API over the tailnet hostname get blocked.
OCONF=/etc/systemd/system/ollama.service.d/strix-halo.conf
if [[ -n "${TSNAME:-}" && -f "$OCONF" ]]; then
    if ! grep -q "OLLAMA_ORIGINS" "$OCONF"; then
        sed -i "/^\[Service\]/a Environment=\"OLLAMA_ORIGINS=https://${TSNAME},https://${TSNAME}:${OLLAMA_PORT},http://localhost,http://localhost:*,http://127.0.0.1,http://127.0.0.1:*\"" "$OCONF"
        echo "==> Added tailnet origin to OLLAMA_ORIGINS"
        systemctl daemon-reload
        systemctl restart ollama
    else
        echo "==> OLLAMA_ORIGINS already set; leaving it alone"
    fi
fi

# ---------- 2. tailscale serve ----------
echo
echo "==> Publishing to the tailnet"
tailscale serve --bg --https=443          "http://127.0.0.1:${WEBUI_PORT}"  || echo "  (webui serve failed)"
tailscale serve --bg --https=${OLLAMA_PORT} "http://127.0.0.1:${OLLAMA_PORT}" || echo "  (ollama serve failed)"

echo
echo "==> tailscale serve status:"
tailscale serve status

echo
echo "############ RESULT ############"
echo "  Open WebUI :  https://${TSNAME}/"
echo "  Ollama API :  https://${TSNAME}:${OLLAMA_PORT}"
echo
echo "  On a client machine:"
echo "     export OLLAMA_HOST=https://${TSNAME}:${OLLAMA_PORT}"
echo
echo "  Listening sockets (nothing should show 0.0.0.0):"
ss -tlnp 2>/dev/null | grep -E ":${WEBUI_PORT}|:${OLLAMA_PORT}" | sed 's/^/    /'
echo "################################"
