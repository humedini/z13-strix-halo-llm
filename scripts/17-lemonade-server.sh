#!/bin/bash
# Installs Lemonade Server: one OpenAI-compatible endpoint that routes to the
# NPU (via FastFlowLM) or the GPU (via llama.cpp), on port 13305.
#
# The PPA also carries amdxdna-dkms and XRT 2.25.0. We want neither:
#   - amdxdna is already in-tree on kernel 7.0 and working. A DKMS module
#     alongside it is a conflict waiting to happen.
#   - FastFlowLM is working against the archive's XRT 2.21.75. Silently
#     upgrading it is an uncontrolled change to a working stack.
# So the PPA is pinned to supply only the lemonade packages.
set -euo pipefail

echo "==> Adding PPA (resolute/26.04 native build)"
add-apt-repository -y ppa:lemonade-team/stable

echo
echo "==> Pinning the PPA to lemonade packages only"
cat > /etc/apt/preferences.d/99-lemonade-ppa << 'PIN'
# Everything from this PPA is refused by default.
Package: *
Pin: release o=LP-PPA-lemonade-team-stable
Pin-Priority: 1

# Except Lemonade itself.
Package: lemonade-server lemonade-desktop
Pin: release o=LP-PPA-lemonade-team-stable
Pin-Priority: 700
PIN

apt-get update

echo
echo "==> Verifying the pin holds (amdxdna-dkms and XRT must NOT be selectable)"
for p in amdxdna-dkms libxrt2 libxrt-alveo2; do
    printf "  %-18s -> %s\n" "$p" "$(apt-cache policy $p 2>/dev/null | grep -oP 'Candidate: \K.*')"
done

echo
echo "==> Installing lemonade-server"
apt-get install -y lemonade-server

echo
echo "==> Confirming nothing unwanted was pulled in"
dpkg -l amdxdna-dkms 2>/dev/null | grep -q '^ii' && echo "  !! amdxdna-dkms WAS installed, remove it: sudo apt remove amdxdna-dkms" || echo "  amdxdna-dkms: not installed (correct)"
printf "  libxrt2 version: %s (expect 2.21.75 from the archive)\n" "$(dpkg -l libxrt2 2>/dev/null | awk '/^ii/{print $3}')"

echo
echo "==> Installed"
command -v lemonade-server >/dev/null && lemonade-server --version 2>&1 | head -2 | sed 's/^/    /' || true
