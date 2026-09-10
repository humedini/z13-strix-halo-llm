#!/bin/bash
# Raises the amdgpu GTT limit so the GPU can address most of system RAM under
# a small (Auto / 512 MB) BIOS UMA carve-out.
#
# Default gttsize is half of system RAM: 61 GiB on this machine under Auto.
# That caps Ollama at ~61 GiB, so laguna-S-2.1 (92 GiB) and gpt-oss:120b
# (65 GiB) will not load. Measured (2026-09-10): models that fit in GTT run at
# the same speed as under the 96 GiB carve-out, so the carve-out was buying
# addressable memory, not bandwidth. Raising gttsize buys the same thing
# without starving the host, which is what halogen-flash-server needs.
#
# 122 GiB RAM. Leave ~16 GiB for the OS and Lemonade's servers:
#   gttsize = 106 GiB = 108544 MiB.
# Note halogen and a >60 GiB Ollama model cannot both be resident anyway;
# this is about flexibility per session, not running everything at once.
#
# Two limits, not one. amdgpu.gttsize is the GPU's view; ttm.pages_limit is
# the page allocator's, and it also defaults to half of RAM. ROCm reports the
# lower of the two, so raising gttsize alone left Ollama at 61.3 GiB (found
# 2026-09-10 after the first reboot). Both are set to the same value here.
# ttm pages are 4 KiB: pages = MiB * 256.
set -euo pipefail
MIB="${1:-108544}"
G=/etc/default/grub
grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" $G || { echo "no GRUB_CMDLINE_LINUX_DEFAULT in $G"; exit 1; }
cp -a $G $G.bak-gttsize-$(date +%Y%m%d-%H%M%S)
PAGES=$(( MIB * 256 ))
for kv in "amdgpu.gttsize=${MIB}" "ttm.pages_limit=${PAGES}" "ttm.page_pool_size=${PAGES}"; do
    key=${kv%%=*}
    if grep -qE "${key//./\\.}=[0-9]+" $G; then
        sed -i -E "s/${key//./\\.}=[0-9]+/${kv}/" $G
    else
        sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"/\1 ${kv}\"/" $G
    fi
done
echo "==> $(grep ^GRUB_CMDLINE_LINUX_DEFAULT $G)"
update-grub
echo; echo "  REBOOT to apply. Then check both:"; echo "    cat /sys/class/drm/card1/device/mem_info_gtt_total"; echo "    cat /sys/module/ttm/parameters/pages_limit   # x4096 = bytes"
echo "  Revert: restore $G.bak-gttsize-* and update-grub, or pass a different MiB value."
