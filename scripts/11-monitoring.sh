#!/bin/bash
# GPU/system monitoring for Strix Halo.
set -euo pipefail

echo "==> nvtop + btop from the archive"
apt-get install -y nvtop btop

echo
echo "==> amdgpu_top (upstream .deb — separates VRAM/GTT, per-engine activity)"
VER=$(curl -fsSL https://api.github.com/repos/Umio-Yasuno/amdgpu_top/releases/latest \
      | grep -oP '"tag_name": "\Kv?[^"]+' | head -1 | sed 's/^v//')
if [[ -z "$VER" ]]; then
    echo "  Could not resolve latest version; skipping amdgpu_top."
else
    TMP=$(mktemp -d)
    # apt drops to the _apt user to download; mktemp -d is 0700, which it
    # cannot read, producing a sandbox warning and a root-fallback download.
    chmod 755 "$TMP"
    URL="https://github.com/Umio-Yasuno/amdgpu_top/releases/download/v${VER}/amdgpu-top_${VER}-1_amd64.deb"
    if curl -fsSL "$URL" -o "$TMP/amdgpu-top.deb"; then
        apt-get install -y "$TMP/amdgpu-top.deb" || echo "  amdgpu_top install failed (non-fatal)"
    else
        echo "  Download failed; skipping amdgpu_top."
    fi
    rm -rf "$TMP"
fi

echo
echo "==> Installed:"
for b in nvtop amdgpu_top btop rocm-smi radeontop; do
    command -v $b >/dev/null && echo "    ✓ $b" || echo "    ✗ $b"
done
