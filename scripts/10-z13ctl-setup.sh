#!/bin/bash
# Grants the 'users' group access to the ASUS control interfaces, so z13ctl
# (RGB, fan curves, TDP, profiles, battery limit) works without root afterwards.
#
# This is the ONLY step here needing root. Everything else — lighting, fan curve,
# autoswitch — runs as your normal user once these rules are in place.
set -euo pipefail

echo "==> Installing udev rules + boot permissions service"
z13ctl setup

echo
echo "==> Enabling the perms service (re-applies late-created sysfs attrs at boot)"
systemctl enable z13ctl-perms.service >/dev/null 2>&1 || true
systemctl start z13ctl-perms.service 2>/dev/null || true

echo
echo "==> Capping battery charge at 80%"
z13ctl batterylimit --set 80
z13ctl batterylimit --get

echo
echo "==> Access check (should now be group-writable by 'users'):"
ls -l /sys/class/power_supply/BAT0/charge_control_end_threshold /dev/hidraw2 /dev/hidraw7 2>/dev/null | sed 's/^/    /'

echo
echo "==> Done. The remaining steps need no root."
