#!/bin/bash
# Completes the ROCm install to match AMD's official Ryzen guide, adapted for
# Ubuntu 26.04.
#
# Deviation from AMD's doc, deliberately: AMD ships amdgpu-install only for
# Ubuntu 24.04 (noble) — repo.radeon.com has no 26.04/resolute build. Mixing
# noble packages into resolute risks libstdc++/python conflicts. Ubuntu 26.04
# ships a native ROCm 7.1 stack instead, which is used here.
#
# AMD's mandatory `--no-dkms` ("inbox drivers are required for ROCm on Ryzen")
# is satisfied inherently: we install no DKMS module and use the kernel's
# in-tree amdgpu on 7.0.
set -euo pipefail

TARGET_USER="${SUDO_USER:-$LOGNAME}"

echo "==> Target user: $TARGET_USER"
echo "==> Groups before: $(id -nG "$TARGET_USER")"

# --- 1. GPU access groups (AMD guide step 4) ---
usermod -a -G render,video "$TARGET_USER"
echo "==> Added $TARGET_USER to render,video"

# --- 2. Full ROCm stack ---
echo
echo "==> Installing the ROCm stack (~129 packages)"
apt-get update
apt-get install -y rocm

# --- 3. Guard against DKMS, which AMD forbids on Ryzen ---
if dpkg -l 2>/dev/null | grep -q amdgpu-dkms; then
    echo
    echo "!! WARNING: amdgpu-dkms is installed. AMD requires inbox drivers on"
    echo "!! Ryzen. Remove it with: sudo apt remove amdgpu-dkms"
fi

echo
echo "==> Verification:"
echo "--- rocminfo agents ---"
rocminfo 2>/dev/null | grep -E "^\s+Name:\s+(gfx|amdgcn)" | sed 's/^/  /'
echo "--- HIP ---"
command -v hipconfig >/dev/null && hipconfig --version 2>/dev/null | sed 's/^/  /' || echo "  hipconfig not found"
echo "--- rocm-smi ---"
rocm-smi 2>/dev/null | head -12 | sed 's/^/  /' || true

echo
echo "############################################################"
echo "  REBOOT REQUIRED for render/video group membership."
echo "  (AMD's guide calls for a reboot at this step too.)"
echo "  After reboot, confirm with:  groups"
echo "############################################################"
