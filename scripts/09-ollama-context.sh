#!/bin/bash
# Pins Ollama's default context length.
#
# Ollama sizes num_ctx from total VRAM: with 96 GiB it defaulted to 262144.
# An 81 GB model (qwen3.5:122b) plus a 256K-token KV cache exceeds VRAM, and the
# overflow lands in system RAM — of which this machine has only 30 GiB, because
# the BIOS UMA split assigns 96 GiB to the GPU.
set -euo pipefail

CONF=/etc/systemd/system/ollama.service.d/strix-halo.conf
CTX="${1:-32768}"
STAMP=$(date +%Y%m%d-%H%M%S)

[[ -f "$CONF" ]] || { echo "ERROR: $CONF not found"; exit 1; }
cp -a "$CONF" "${CONF}.bak.${STAMP}"

if grep -q "OLLAMA_CONTEXT_LENGTH" "$CONF"; then
    sed -i "s|^Environment=\"OLLAMA_CONTEXT_LENGTH=.*|Environment=\"OLLAMA_CONTEXT_LENGTH=${CTX}\"|" "$CONF"
    echo "==> Updated OLLAMA_CONTEXT_LENGTH to ${CTX}"
else
    sed -i "/^\[Service\]/a Environment=\"OLLAMA_CONTEXT_LENGTH=${CTX}\"" "$CONF"
    echo "==> Added OLLAMA_CONTEXT_LENGTH=${CTX}"
fi

# Clear any transient override from `systemctl set-environment`, which would
# otherwise win over the unit file.
systemctl unset-environment OLLAMA_CONTEXT_LENGTH 2>/dev/null || true

systemctl daemon-reload
systemctl restart ollama

echo
echo "==> Drop-in now:"
sed 's/^/    /' "$CONF"
echo
echo "==> Effective environment:"
systemctl show ollama -p Environment | tr ' ' '\n' | grep -E "OLLAMA_|HIP_|GPU_" | sed 's/^/    /'
echo
echo "==> Confirming from the service log:"
sleep 3
journalctl -u ollama -b --no-pager 2>/dev/null | grep -oE "OLLAMA_CONTEXT_LENGTH:[0-9]+" | tail -1 | sed 's/^/    /'
echo
echo "  Backup: ${CONF}.bak.${STAMP}"
echo "  To change later:  sudo ~/z13-setup/09-ollama-context.sh 65536"
