#!/bin/bash
# Installs FastFlowLM, the NPU inference runtime, plus AMD XRT.
#
# Prerequisites already satisfied on this machine:
#   XDNA2 NPU (RyzenAI-npu5)     Strix Halo is explicitly supported
#   kernel 7.0 with amdxdna      FastFlowLM requires 7.0+, this is exactly it
#   NPU firmware 1.1.2.65        requirement is >= 1.1.0.0
#   user in 'render' group       /dev/accel/accel0 is root:render
#
# XRT comes from the Ubuntu archive (libxrt2, libxrt-npu2), not from AMD.
set -euo pipefail

# Resolve relative to this script, not $HOME: under sudo, ~ is /root.
SCRIPT_DIR=$(cd -P "$(dirname "$(readlink -f "$0")")" && pwd)
DEB="${SCRIPT_DIR}/fastflowlm_1.0.4_ubuntu26.04_amd64.deb"
if [[ ! -f "$DEB" ]]; then
    echo "Missing $DEB"
    echo "Re-download with:"
    echo "  curl -sL https://github.com/ROCm/FastFlowLM/releases/download/v1.0.4/fastflowlm_1.0.4_ubuntu26.04_amd64.deb -o \"$DEB\""
    exit 1
fi

echo "==> Pre-flight"
printf "  NPU device:   %s\n" "$(ls /dev/accel/accel0 2>/dev/null || echo MISSING)"
printf "  firmware:     %s\n" "$(cat /sys/bus/pci/drivers/amdxdna/*/fw_version 2>/dev/null | head -1)"
printf "  kernel:       %s\n" "$(uname -r)"

echo
echo "==> Installing FastFlowLM + XRT"
apt-get install -y "$DEB"

echo
echo "==> Verification"
command -v flm >/dev/null && echo "  flm: $(flm --version 2>/dev/null | head -1 || echo installed)" || echo "  flm NOT on PATH"
command -v xrt-smi >/dev/null && xrt-smi examine 2>&1 | head -12 | sed 's/^/    /' || true

echo
echo "############################################################"
echo "  Next, as your normal user (no root):"
echo "     flm list              # models available for the NPU"
echo "     flm run llama3.2:1b   # smoke test"
echo "     flm serve             # OpenAI-compatible server"
echo
echo "  Expect the NPU to be SLOWER than the iGPU for generation"
echo "  (roughly 2.4x slower decode) but faster to first token and"
echo "  at about half the power. Its real value is running"
echo "  alongside the GPU, not replacing it."
echo "############################################################"
