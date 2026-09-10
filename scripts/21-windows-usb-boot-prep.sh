#!/bin/bash
# Prepares a Windows install on an external USB enclosure so it can boot.
#
# Moving an NVMe with Windows on it into a USB enclosure changes the storage
# transport from NVMe to USB mass storage. Windows' boot-critical driver set does
# not include USB storage class drivers, so it panics with INACCESSIBLE_BOOT_DEVICE
# before it can load them.
#
# Two changes, applied offline to the SYSTEM hive:
#   1. BootDriverFlags = 0x14 under HKLM\SYSTEM\HardwareConfig\{GUID}
#      Tells Windows to load USB and storage class drivers early in boot.
#   2. Start = 0 (boot start) for the USB storage service stack
#      Belt and braces: makes those drivers boot-critical explicitly.
#
# The SYSTEM hive is backed up first. Nothing else on the drive is touched.
set -euo pipefail

command -v hivexget >/dev/null 2>&1 || { echo "Run: sudo apt install -y libhivex-bin python3-hivex chntpw"; exit 1; }

MNT=/mnt/winboot
DEV="${1:-}"

if [[ -z "$DEV" ]]; then
    echo "Windows-looking partitions:"
    lsblk -o NAME,SIZE,FSTYPE,LABEL,MODEL -P 2>/dev/null | grep -i 'FSTYPE="ntfs"' | sed 's/^/  /'
    echo
    echo "Usage: $0 /dev/sdXN     (the large NTFS partition, not the 100 MB EFI one)"
    exit 1
fi

echo "==> Mounting $DEV"
mkdir -p "$MNT"
mount -t ntfs3 -o rw "$DEV" "$MNT" 2>/dev/null || mount -t ntfs-3g -o rw "$DEV" "$MNT"

HIVE="$MNT/Windows/System32/config/SYSTEM"
[[ -f "$HIVE" ]] || { echo "No SYSTEM hive at $HIVE - wrong partition?"; umount "$MNT"; exit 1; }

STAMP=$(date +%Y%m%d-%H%M%S)
cp -a "$HIVE" "$HIVE.bak-$STAMP"
echo "==> Backed up hive to SYSTEM.bak-$STAMP ($(du -h "$HIVE.bak-$STAMP" | cut -f1))"

python3 - "$HIVE" << 'PYEOF'
import sys, hivex
h = hivex.Hivex(sys.argv[1], write=True)
root = h.root()

def child(node, name):
    for c in h.node_children(node):
        if h.node_name(c).lower() == name.lower():
            return c
    return None

changed = 0

# 1. BootDriverFlags = 0x14 on every HardwareConfig GUID
hw = child(root, "HardwareConfig")
if hw:
    for g in h.node_children(hw):
        h.node_set_value(g, {"key": "BootDriverFlags", "t": 4,
                             "value": (0x14).to_bytes(4, "little")})
        print(f"    BootDriverFlags=0x14 on HardwareConfig\\{h.node_name(g)}")
        changed += 1
else:
    print("    no HardwareConfig key found")

# 2. Boot-start the USB storage stack in each ControlSet
for cs in h.node_children(root):
    n = h.node_name(cs)
    if not n.lower().startswith("controlset"):
        continue
    svcs = child(cs, "Services")
    if not svcs:
        continue
    for drv in ("USBSTOR", "UASPStor", "USBXHCI", "usbehci", "usbhub",
                "stornvme", "storahci", "iaStorV", "disk", "partmgr", "volmgr"):
        d = child(svcs, drv)
        if d:
            h.node_set_value(d, {"key": "Start", "t": 4,
                                 "value": (0).to_bytes(4, "little")})
            changed += 1
    print(f"    boot-start applied under {n}\\Services")

h.commit(None)
print(f"    {changed} values written")
PYEOF

sync
umount "$MNT"
echo
echo "==> Done. Now:"
echo "     1. Reboot and enter the boot menu (hold ESC or F8 on ASUS)"
echo "     2. Pick the USB device"
echo "     3. First boot will be slow while Windows installs USB storage drivers"
echo
echo "  If it still fails, restore the hive: mount the partition and"
echo "  copy SYSTEM.bak-$STAMP back over SYSTEM."
