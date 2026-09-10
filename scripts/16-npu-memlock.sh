#!/bin/bash
# Raises the memlock limit so the NPU can pin its buffers.
#
# `flm validate` fails with:
#   [ERROR] Memlock limit is too low (8MB). Please raise the limit or set to infinity.
#
# 8 MB is the kernel default. The NPU pins model buffers well beyond that.
#
# Both paths need setting: PAM limits cover login shells, and systemd's
# DefaultLimitMEMLOCK covers user services and anything launched from the
# graphical session, which does not inherit PAM limits.
set -euo pipefail

echo "==> Before: soft=$(ulimit -S -l) KB  hard=$(ulimit -H -l) KB"

install -d -m 755 /etc/security/limits.d
cat > /etc/security/limits.d/95-npu-memlock.conf << 'CONF'
# Raised for the AMD XDNA2 NPU (FastFlowLM). The 8 MB default is far below
# what the NPU needs to pin.
*    soft    memlock    unlimited
*    hard    memlock    unlimited
root soft    memlock    unlimited
root hard    memlock    unlimited
CONF
echo "==> Wrote /etc/security/limits.d/95-npu-memlock.conf"

for f in /etc/systemd/system.conf /etc/systemd/user.conf; do
    d="${f%.conf}.conf.d"
    install -d -m 755 "$d"
    cat > "${d}/95-npu-memlock.conf" << 'CONF'
[Manager]
DefaultLimitMEMLOCK=infinity
CONF
    echo "==> Wrote ${d}/95-npu-memlock.conf"
done

systemctl daemon-reexec 2>/dev/null || true

echo
echo "############################################################"
echo "  LOG OUT AND BACK IN (or reboot) for this to take effect."
echo "  PAM limits are applied at session creation; the current"
echo "  session keeps the old 8 MB value."
echo
echo "  Then verify:"
echo "     ulimit -l        # expect: unlimited"
echo "     flm validate     # expect: no errors"
echo "############################################################"
