# 16. Living with it: sleep, docks, SD cards and a bigger SSD

Two months of daily use after the build. None of this is about inference speed. All of it cost time.

## Sleep sometimes does not wake

Twice in 13 sleeps over a month, the machine went into s2idle and never came back; a hard reset was the only way out. Both times it was on AC with an HDMI monitor attached and no model loaded. The journal of the failed boot ends at `PM: suspend entry (s2idle)` with no `suspend exit` and nothing else: no kernel warning beforehand, no pstore record, no AMD reset reason. Sleeps of 17 to 42 hours woke fine on other days.

What that rules out: battery drain, a loaded model, and any one recent change (the second failure predates the SD card hook below). The setup script already installs a sleep hook that unbinds the ASUS HID and MMC devices and limits wake sources, which says this chassis has known sleep quirks.

Workaround: no idle suspend on AC. Battery idle suspend and lid suspend are left on.

```bash
gsettings set org.gnome.settings-daemon.plugins.power sleep-inactive-ac-type nothing
```

To catch it next time, boot with `pm_debug_messages no_console_suspend` or enable ramoops. Not yet done.

## A USB4 dock: everything except video

A Razer USB4 dock links at 40 Gb/s and `bolt` authorises it automatically. Its 2.5GbE port (Realtek RTL8156, `r8152`), USB hubs and card readers all work with in-tree drivers. Razer publishes no Linux software, and `fwupd` sees the controller but LVFS has no firmware for it.

**Video over the dock does not work reliably** on kernel 7.0.0-31. A monitor on the dock's HDMI caused repeated `amdgpu` `flip_done timed out` and `commit wait timed out` errors with WARN traces, every 10 seconds exactly, which is the DRM atomic commit timeout. In GNOME that showed up as a 10 to 15 second freeze whenever the pointer moved onto the external screen, ending in the "keep these display settings?" dialog. No link training or EDID errors, and GNOME logged nothing.

The same monitor on the Z13's own HDMI port (`HDMI-A-1`) has had no errors at 4K. A monitor through the dock shows up as `DP-n`, so check which one you are looking at before deciding dock video works. Untried: the dock's DisplayPort output, a lower refresh rate, and newer kernels.

## SD cards: ext4 does not automount, and suspend drops them

A microSD card makes a good Steam library. Two things got in the way.

**Ubuntu deliberately does not automount ext4 cards.** `/usr/lib/udev/rules.d/64-ext4.rules` sets `UDISKS_AUTO=0` on every ext4 volume, so GNOME only mounts the card once you open it in Files. Steam started before that never sees its library and offers to re-add it every time. A udev rule for that one filesystem fixes it:

```
# /etc/udev/rules.d/99-steam-card-automount.rules
SUBSYSTEM=="block", ENV{ID_FS_UUID}=="<card-uuid>", ENV{UDISKS_AUTO}="1"
```

Check with `udisksctl info -b /dev/mmcblk0p1`, where `HintAuto` should read true. Polkit only allows mounting once the session is active, which can be a second or two after login, so a login-time `udisksctl mount` needs to retry rather than give up after one try.

**The reader drops the card on suspend.** The Genesys GL9755 reader loses the card in s2idle and ext4 aborts its journal. On wake the reader logs SDHCI timeouts, finds the card again and it is remounted. A `system-sleep` hook that syncs and unmounts before sleep, and remounts after, keeps the filesystem clean. If Steam was running, restart it afterwards.

## A 2 TB SSD

The Z13 takes an M.2 **2230** drive, and the slot is **PCIe Gen4 x4**, so a Gen5 drive runs at Gen4 speeds. The original was a 1 TB DRAM-less Micron 2450. It was replaced with a 2 TB SanDisk Optimus GX 7100M, also DRAM-less, using a standalone M.2 cloner, then the root partition grown with `growpart` and `resize2fs`.

**Trim straight after cloning.** A sector-by-sector clone writes every block, so the new drive believes the whole old disk is in use. `fstrim -av` released 1.2 TiB. Even after that, the first sustained write test fell to about 0.5 GB/s after a 4 GiB cache; the drive was still reorganising the cloned data in the background. After an hour idle it wrote at 3.1 GB/s flat across 64 GiB.

| Test, `dd` direct I/O | Micron 2450, 1 TB | SanDisk 7100M, 2 TB |
|---|---|---|
| Sequential write, 16 GiB | 1.9 GB/s | 3.5 GB/s |
| Sustained write, 64 GiB | 1.7 GB/s | 3.1 GB/s, flat |
| Sequential read | 2.9 GB/s | 3.6 GB/s |

Reads stopped at 3.6 to 3.7 GB/s however they were driven: 1 MB or 4 MB blocks, one to sixteen parallel streams, zeros or random data. The link was confirmed at 16 GT/s x4 under load.

**`iommu=pt` raised writes and coincided with SD card damage.** The NVMe controller sits behind the IOMMU in translated mode. One boot with `iommu=pt` took sequential writes from 3.5 to 5.7 GB/s and left reads unchanged, so the read ceiling is in the drive, not the IOMMU. On that same boot the SD card's ext4 filesystem reported a bad block bitmap checksum two seconds after mounting and went read-only, the first such error in 30 days. `iommu=pt` was removed and the card repaired with `e2fsck`. The cause is unproven; it could be passthrough DMA and the GL9755 reader, or old damage read for the first time. It was not retried.

## AMD PerfOpt, Linux 7.4

AMD PerfOpt lets the iGPU bypass the IOMMU for system memory access. It is queued for Linux 7.4 and on by default for AMD iGPUs (`amdgpu.iommu_perfopt=0` turns it off). [Phoronix measured](https://www.phoronix.com/review/amd-perfopt) 18 to 23 percent on small iGPUs but only 2 to 4 percent on Strix Halo. Here the iGPU's IOMMU group is already in passthrough (`identity`) while the IOMMU stays on for USB4 protection, so the gain is likely at the bottom of that range. It is the cleaner answer to "turn the IOMMU off" advice for [Halogen](12-halogen.md), because it keeps the protection. Not tested yet.
