#!/bin/bash
# Makes the 80% battery charge limit survive reboot AND resume-from-suspend.
#
# charge_control_end_threshold is a plain sysfs value with no firmware backing,
# so it resets to 100 on every boot. asus_nb_wmi also creates it late in probe(),
# after udev events fire, so the unit waits for the attribute to appear.
set -euo pipefail

LIMIT="${1:-80}"
UNIT=/etc/systemd/system/asus-battery-limit.service
ATTR=/sys/class/power_supply/BAT0/charge_control_end_threshold

cat > "$UNIT" << UNITEOF
[Unit]
Description=Restore ASUS battery charge limit (${LIMIT}%)
After=multi-user.target suspend.target hibernate.target hybrid-sleep.target

[Service]
Type=oneshot
RemainAfterExit=yes
# The attribute is created late by asus_nb_wmi; wait for it rather than racing.
ExecStartPre=/bin/sh -c 'for i in \$(seq 1 30); do [ -e ${ATTR} ] && exit 0; sleep 1; done; exit 1'
ExecStart=/bin/sh -c 'echo ${LIMIT} > ${ATTR}'

[Install]
WantedBy=multi-user.target suspend.target hibernate.target hybrid-sleep.target
UNITEOF

systemctl daemon-reload
systemctl enable --now asus-battery-limit.service

echo "==> Unit installed and started"
echo -n "==> Limit now: "; cat "$ATTR"
echo
systemctl is-enabled asus-battery-limit.service | sed 's/^/    enabled: /'
echo
echo "  Change later:  sudo ~/z13-setup/12-battery-limit-persist.sh 100"
