#!/bin/bash
# Disables Wi-Fi power save on the MT7925.
#
# Symptom: LAN ping to a local host averaged 86 ms with 65 ms jitter and a 159 ms
# max, and throughput collapsed to roughly 43 KB/s, despite a -39 dBm signal and a
# 1.2 Gbit/s PHY rate. The AP beacons every 100 ms with DTIM 2, so a sleeping client
# buffers for up to 200 ms, which matches the observed maximum.
#
# Sets it both on the active connection and as the NetworkManager default, so new
# connections do not reintroduce it.
set -euo pipefail

IFACE="${1:-wlp194s0}"
CONN=$(nmcli -t -f NAME,DEVICE connection show --active | grep ":${IFACE}$" | cut -d: -f1)
[[ -z "$CONN" ]] && { echo "No active connection on ${IFACE}"; exit 1; }

echo "==> Interface: ${IFACE}, connection: ${CONN}"
echo "==> Before: $(iw dev ${IFACE} get power_save 2>/dev/null)"

# 2 = disable, 3 = enable, 0 = use default
nmcli connection modify "$CONN" 802-11-wireless.powersave 2

# Make it the default for any future Wi-Fi connection too.
install -d -m 755 /etc/NetworkManager/conf.d
cat > /etc/NetworkManager/conf.d/wifi-powersave-off.conf << 'CONF'
[connection]
wifi.powersave = 2
CONF

# Apply immediately without waiting for a reconnect.
iw dev "${IFACE}" set power_save off 2>/dev/null || true

echo "==> After:  $(iw dev ${IFACE} get power_save 2>/dev/null)"
echo
echo "==> Latency check:"
ping -c 8 -i 0.3 <lan-host> 2>/dev/null | tail -2 | sed 's/^/    /'
echo
echo "  Revert with: sudo nmcli connection modify \"$CONN\" 802-11-wireless.powersave 3"
echo "               sudo rm /etc/NetworkManager/conf.d/wifi-powersave-off.conf"
