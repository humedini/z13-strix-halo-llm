#!/bin/bash
# Corrects two things the strix-halo LLM module configured on this machine:
#   1. HSA_OVERRIDE_GFX_VERSION=11.0.0  (wrong for gfx1151)
#   2. OLLAMA_HOST=0.0.0.0              (binds the unauthenticated API to all interfaces)
#
# Also prints a root-context diagnostic explaining why the module's native-gfx1151
# detection returned false, which we could not reproduce as an unprivileged user.
set -uo pipefail

PROFILE=/etc/profile.d/strix-halo-rocm.sh
OLLAMA_CONF=/etc/systemd/system/ollama.service.d/strix-halo.conf
STAMP=$(date +%Y%m%d-%H%M%S)

echo "############ DIAGNOSTIC (root context) ############"
echo -n "rocminfo on PATH: "; command -v rocminfo || echo "NOT FOUND"
echo -n "rocminfo exit code: "; rocminfo >/dev/null 2>&1; echo $?
echo -n "gfx1151 enumerated as root: "
if rocminfo 2>/dev/null | grep -q gfx1151; then echo "YES"; else echo "NO  <-- this is why the override was written"; fi
echo -n "kfd access: "; ls -l /dev/kfd 2>/dev/null || echo "/dev/kfd MISSING as root"
echo "###################################################"
echo

# ---- 1. profile.d ----
if [[ -f "$PROFILE" ]] && grep -q '^export HSA_OVERRIDE_GFX_VERSION' "$PROFILE"; then
    cp -a "$PROFILE" "${PROFILE}.bak.${STAMP}"
    sed -i '/^export HSA_OVERRIDE_GFX_VERSION/d' "$PROFILE"
    sed -i 's|^# Emulate gfx1100.*|# gfx1151 is natively supported by ROCm 7.1.1 — no HSA override needed.|' "$PROFILE"
    echo "==> $PROFILE : removed HSA_OVERRIDE_GFX_VERSION (backup: ${PROFILE}.bak.${STAMP})"
else
    echo "==> $PROFILE : no override present, nothing to do"
fi

# ---- 2. ollama systemd drop-in ----
if [[ -f "$OLLAMA_CONF" ]]; then
    cp -a "$OLLAMA_CONF" "${OLLAMA_CONF}.bak.${STAMP}"
    sed -i '/HSA_OVERRIDE_GFX_VERSION/d' "$OLLAMA_CONF"
    sed -i 's|^# Emulate gfx1100.*|# gfx1151 native — no HSA override.|' "$OLLAMA_CONF"
    # Bind the API to loopback. It has no authentication; 0.0.0.0 exposes every
    # loaded model to anyone on the current network (incl. public Wi-Fi).
    sed -i 's|Environment="OLLAMA_HOST=0.0.0.0"|Environment="OLLAMA_HOST=127.0.0.1"|' "$OLLAMA_CONF"
    echo "==> $OLLAMA_CONF : removed HSA override, bound API to 127.0.0.1"
    echo "    (backup: ${OLLAMA_CONF}.bak.${STAMP})"
    systemctl daemon-reload
    systemctl restart ollama
    echo "==> ollama restarted"
else
    echo "==> $OLLAMA_CONF : not present"
fi

echo
echo "==> Resulting config:"
echo "--- $PROFILE ---"; cat "$PROFILE" 2>/dev/null
echo "--- $OLLAMA_CONF ---"; cat "$OLLAMA_CONF" 2>/dev/null
echo
echo "==> Effective ollama environment:"
systemctl show ollama -p Environment
