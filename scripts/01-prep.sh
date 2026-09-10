#!/bin/bash
# Pre-flight for the Strix Halo setup run.
# Installs tooling the setup script assumes, plus verification utilities.
set -euo pipefail

echo "==> Refreshing package lists"
apt-get update

echo "==> Installing build/base tooling (setup script needs git + build-essential)"
apt-get install -y git build-essential curl wget ca-certificates gnupg

echo "==> Installing GPU/system verification tools"
apt-get install -y mesa-utils vulkan-tools lm-sensors

echo "==> Installing ROCm userspace from the Ubuntu archive (7.1.1)"
apt-get install -y rocminfo rocm-smi

echo "==> Detecting sensors (non-interactive, safe defaults)"
yes "" | sensors-detect --auto >/dev/null 2>&1 || true

echo
echo "==> Done. Verification:"
echo "--- GPU ---"
glxinfo -B 2>/dev/null | grep -E "OpenGL renderer|OpenGL core profile version" || true
vulkaninfo --summary 2>/dev/null | grep -E "deviceName|driverName" || true
echo "--- ROCm ---"
rocminfo 2>/dev/null | grep -E "Name:|gfx" | head -10 || true
