#!/bin/bash
# Applies Ollama tuning that is widely reported as a win on NVIDIA hardware
# and was worth testing here. Measured: no benefit on ROCm/gfx1151; see docs/05-benchmarks.md.
#
#   OLLAMA_FLASH_ATTENTION=1   faster prefill, lower KV memory
#   OLLAMA_KV_CACHE_TYPE=q8_0  roughly halves KV cache size (requires flash attention)
#   OLLAMA_KEEP_ALIVE          how long a model stays resident (argument, default 30m)
set -euo pipefail

CONF=/etc/systemd/system/ollama.service.d/strix-halo.conf
KEEP="${1:-30m}"
STAMP=$(date +%Y%m%d-%H%M%S)

[[ -f "$CONF" ]] || { echo "ERROR: $CONF not found"; exit 1; }
cp -a "$CONF" "${CONF}.bak.${STAMP}"

set_env() {
    local k="$1" v="$2"
    if grep -q "\"${k}=" "$CONF"; then
        sed -i "s|^Environment=\"${k}=.*|Environment=\"${k}=${v}\"|" "$CONF"
    else
        sed -i "/^\[Service\]/a Environment=\"${k}=${v}\"" "$CONF"
    fi
    echo "  ${k}=${v}"
}

echo "==> Setting:"
set_env OLLAMA_FLASH_ATTENTION 1
set_env OLLAMA_KV_CACHE_TYPE q8_0
set_env OLLAMA_KEEP_ALIVE "$KEEP"

systemctl daemon-reload
systemctl restart ollama

echo
echo "==> Effective environment:"
systemctl show ollama -p Environment | tr ' ' '\n' | grep -E "OLLAMA_|HIP_|GPU_" | sed 's/^/    /'
echo
echo "  Backup: ${CONF}.bak.${STAMP}"
echo "  Different keep-alive: sudo ~/z13-setup/14-ollama-tuning.sh 1h   (or -1 for forever)"
