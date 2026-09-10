#!/bin/bash
# Installs sshd and binds it to the tailnet interface only.
#
# Consistent with the rest of this machine: nothing listens on a LAN-facing
# address. sshd binds the Tailscale IP and loopback, so it is unreachable from
# any network this tablet joins, and reachable from every device on the tailnet.
#
# Deliberately NOT using Tailscale SSH: the tailnet ACL runs SSH in "check"
# mode, which forces a browser re-approval roughly every 12 hours (see the
# which cannot be done headless). Regular sshd over the tailnet avoids that.
set -euo pipefail

TSIP=$(tailscale ip -4 2>/dev/null | head -1)
[[ -n "$TSIP" ]] || { echo "No Tailscale IPv4 address; is tailscaled up?"; exit 1; }
TS6=$(tailscale ip -6 2>/dev/null | head -1)

echo "==> Installing openssh-server"
apt-get install -y openssh-server

echo
echo "==> Binding to the tailnet only (${TSIP})"
install -d -m 755 /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/10-tailnet-only.conf << CONF
# Listen on the tailnet and loopback only. Never on Wi-Fi or Ethernet.
ListenAddress ${TSIP}
ListenAddress 127.0.0.1
${TS6:+ListenAddress $TS6}

# Tailscale already authenticates the network. Keep sshd's own posture sane.
PermitRootLogin no
X11Forwarding no
CONF

systemctl enable ssh >/dev/null 2>&1 || true
systemctl restart ssh
sleep 2

echo
echo "==> Listening sockets (must NOT include 0.0.0.0:22)"
ss -tlnp 2>/dev/null | grep ":22 " | sed 's/^/    /' || echo "    nothing on 22 - check 'systemctl status ssh'"

echo
echo "############################################################"
echo "  From any tailnet device:"
echo "     ssh user@<hostname>          (MagicDNS)"
echo "     ssh user@${TSIP}"
echo
echo "  Password auth is still enabled, so you can get in now."
echo "  Once you have copied a key over:"
echo "     ssh-copy-id user@<hostname>      # from your Mac"
echo "  then harden it:"
echo "     echo 'PasswordAuthentication no' | sudo tee -a \\"
echo "       /etc/ssh/sshd_config.d/10-tailnet-only.conf && sudo systemctl restart ssh"
echo "############################################################"
