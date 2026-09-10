#!/bin/bash
# Installs Tailscale from the official repo (Ubuntu 26.04 "resolute" channel).
set -euo pipefail

. /etc/os-release
CODENAME="${VERSION_CODENAME:-resolute}"

if command -v tailscale >/dev/null 2>&1; then
    echo "==> Tailscale already installed: $(tailscale version | head -1)"
else
    echo "==> Adding Tailscale package repository (${CODENAME})"
    install -d -m 0755 /usr/share/keyrings
    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${CODENAME}.noarmor.gpg" \
        -o /usr/share/keyrings/tailscale-archive-keyring.gpg
    chmod 0644 /usr/share/keyrings/tailscale-archive-keyring.gpg

    curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${CODENAME}.tailscale-keyring.list" \
        -o /etc/apt/sources.list.d/tailscale.list

    apt-get update
    apt-get install -y tailscale
fi

systemctl enable --now tailscaled
echo
echo "==> tailscaled: $(systemctl is-active tailscaled)"
echo "==> version:    $(tailscale version | head -1)"
echo
echo "############################################################"
echo "  NEXT: join your tailnet. This prints a URL to open in a"
echo "  browser and authenticate — it cannot be automated."
echo
echo "      sudo tailscale up"
echo
echo "  Then, in the Tailscale admin console, enable:"
echo "      Settings -> Features -> HTTPS Certificates"
echo "  (required for 'tailscale serve' to issue TLS certs)"
echo "############################################################"
