#!/bin/bash
# Fixes ARP behaviour for two interfaces on the same subnet (Wi-Fi + wired).
#
# Symptom: the wired interface gets a DHCP address but no routes, and
# NetworkManager logs "conflict detected for IP address ... with host <wifi MAC>".
#
# Cause: Linux defaults to arp_ignore=0 and arp_announce=0, so ANY interface
# answers ARP for ANY local address. The Wi-Fi card answers for the wired
# card's IP, NM's address-conflict detection sees the IP "owned" by another
# MAC, and withdraws the routes. Even if routes survive, the switch can learn
# the wired IP against the Wi-Fi MAC and silently deliver inbound over Wi-Fi.
#
#   arp_ignore=1    reply only if the target IP is on the receiving interface
#   arp_announce=2  use the best local source address for the outgoing interface
#
# Standard hygiene for any multi-homed host on one subnet.
set -euo pipefail

cat > /etc/sysctl.d/90-arp-multihome.conf << 'CONF'
net.ipv4.conf.all.arp_ignore = 1
net.ipv4.conf.all.arp_announce = 2
net.ipv4.conf.default.arp_ignore = 1
net.ipv4.conf.default.arp_announce = 2
CONF
sysctl -q --system
echo "==> applied:"
sysctl net.ipv4.conf.all.arp_ignore net.ipv4.conf.all.arp_announce | sed 's/^/    /'
echo
echo "  With this in place, ipv4.dad-timeout can be restored on the wired profile:"
echo "    nmcli connection modify \"Wired connection 2\" ipv4.dad-timeout -1"
