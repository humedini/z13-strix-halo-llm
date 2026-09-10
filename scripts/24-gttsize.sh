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
set -euo pipefail
MIB="${1:-108544}"
G=/etc/default/grub
grep -q "^GRUB_CMDLINE_LINUX_DEFAULT=" $G || { echo "no GRUB_CMDLINE_LINUX_DEFAULT in $G"; exit 1; }
cp -a $G $G.bak-gttsize-$(date +%Y%m%d-%H%M%S)
if grep -qE 'amdgpu\.gttsize=[0-9]+' $G; then
    sed -i -E "s/amdgpu\.gttsize=[0-9]+/amdgpu.gttsize=${MIB}/" $G
else
    sed -i -E "s/^(GRUB_CMDLINE_LINUX_DEFAULT=\"[^\"]*)\"/\1 amdgpu.gttsize=${MIB}\"/" $G
fi
echo "==> $(grep ^GRUB_CMDLINE_LINUX_DEFAULT $G)"
update-grub
echo; echo "  REBOOT to apply. Then: cat /sys/class/drm/card1/device/mem_info_gtt_total"
echo "  Revert: restore $G.bak-gttsize-* and update-grub, or pass a different MiB value."
