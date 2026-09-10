# 01. Hardware and what works untouched

## The machine

ASUS ROG Flow Z13 GZ302EA, 2025 model. A 13 inch tablet with a detachable keyboard folio, built around AMD's Strix Halo APU.

| | |
|---|---|
| APU | AMD Ryzen AI MAX+ 395, 16 Zen 5 cores, 32 threads |
| GPU | Radeon 8060S, RDNA 3.5, 40 compute units, `gfx1151` |
| NPU | XDNA2, reported as `RyzenAI-npu5`, 8 columns, 50 TOPS |
| Memory | 128 GB LPDDR5X-8000 on a 256 bit bus, roughly 256 GB/s |
| Storage | one M.2 2230 NVMe slot |
| Ports | 2x USB4 Type-C, 1x USB 3.2 Gen2 Type-A, microSD |
| Wi-Fi | MediaTek MT7925, Wi-Fi 7 |
| Display | 2560x1600 IPS, 180 Hz, touch and stylus |
| BIOS | GZ302EA.314, July 2026 at time of writing |

The single most consequential fact about this hardware is that the 128 GB is **unified memory** shared between CPU and GPU over a single ~256 GB/s bus. Everything about inference performance follows from that. See [inference](04-inference.md).

## The BIOS memory split

The BIOS lets you assign a fixed portion of the 128 GB to the GPU as dedicated VRAM. This build ran **96 GiB VRAM, 30 GiB system** for most of what is documented here, then moved to **Auto** (0.5 GiB VRAM, 122 GiB system, 61 GiB GTT) to run [Halogen](12-halogen.md). Both are measured; see below.

That split is the right one for large model inference: an 81 GB model loads entirely into VRAM with room for KV cache, and nothing spills. It is the wrong one for almost anything else, because 30 GiB of system RAM is not much.

Linux does not need a large fixed split in principle. `amdgpu` can allocate system memory to the GPU dynamically through GTT. In practice, though, GTT is capped at half of system RAM, so with a small VRAM split the GPU's usable memory is limited by that cap rather than by the physical 128 GB. A large fixed VRAM split is how you actually get to use the memory for models.

The cost is real. With 30 GiB of system RAM:

- A 16 GB PyTorch venv for diarisation is a noticeable fraction of it
- Lemonade's backend server processes, at 0.6 to 2.3 GB each, accumulate faster than they would elsewhere
- GTT is only 15 GiB, so a model that overflows VRAM has very little cushion before throughput collapses

Watch `mem_info_gtt_used` under `/sys/class/drm/card1/device/`. Under a carve-out it should stay at zero during inference; if it starts filling, weights are spilling into system RAM and everything slows down. Under Auto it is where the weights live, and the number to watch is `mem_info_gtt_total`, the cap.

### What the carve-out is actually worth

The argument for a large carve-out is that the GPU reaches memory faster through its own aperture than through GTT. Measured on identical weights and prompts, same TDP, three runs each, the carve-out is worth **7 to 9 percent on generation and nothing on prefill**, with prefill through GTT actually faster:

| Model | Carve-out generation | GTT generation | Carve-out prefill | GTT prefill |
|---|---|---|---|---|
| `qwen3-coder:30b-a3b` | 50.8 tok/s | 46.0 tok/s | 823 tok/s | 1267 tok/s |
| `gpt-oss:20b` | 46.8 tok/s | 43.5 tok/s | 1548 tok/s | 1613 tok/s |

So the fixed split is not free performance, but it is small. What Auto gives back is 92 GiB of system RAM for everything that is not a model: PyTorch venvs, Lemonade's backend servers, Docker, a browser, and engines like Halogen that allocate from the host side and cannot see a carve-out at all.

The one thing Auto takes away is the GTT cap. At half of system RAM it is 61 GiB, so `gpt-oss:120b` at 65 GB and `laguna-S-2.1` at 92 GB no longer load in Ollama. `amdgpu.gttsize=<MiB>` on the kernel command line raises it; `scripts/24-gttsize.sh` sets 106 GiB and needs a reboot. Raising it does not reserve anything; it only permits.

Switching is a BIOS trip either way: Advanced, UMA Frame Buffer Size. F2 at power on, or `systemctl reboot --firmware-setup`.

## What works on kernel 7.0 with no intervention

Ubuntu 26.04 ships kernel 7.0, and the hardware support is in tree. Verified working from a clean install, before any script ran:

| Component | Driver | Notes |
|---|---|---|
| Radeon 8060S | `amdgpu` | Mesa 26.0.8, RADV and radeonsi, 96 GiB VRAM visible |
| MT7925 Wi-Fi + Bluetooth | `mt7925e`, `btmtk` | Wi-Fi 7 capable, though the access point decides what you get |
| ELAN9008 touchscreen + stylus | `hid_multitouch`, `i2c_hid` | seven input nodes including pressure |
| Detachable keyboard + touchpad | `hid_asus` | disappears cleanly when detached |
| Auto rotate | `amd_sfh` + `iio-sensor-proxy` | accelerometer through the sensor fusion hub |
| Camera | `uvcvideo` | four `/dev/video*` nodes |
| Audio | `snd_hda_intel` with ALC294 | speakers, headphones, mic, through PipeWire |
| NPU | `amdxdna` | `/dev/accel/accel0`, firmware 1.1.2.65 |
| ASUS platform | `asus_armoury`, `asus_nb_wmi` | TDP limits, fan curve hwmon, charge limit, keyboard backlight |
| Thunderbolt / USB4 | `thunderbolt` | two host routers, two domains, security level `user` |

`fwupdmgr` reports all 22 firmware devices current. Nothing needed updating.

The one thing that is **not** in tree is hibernation, and that is a policy decision rather than a driver gap. See [gotchas](11-gotchas.md).

## Things the kernel does that are not obvious

**`/dev/kfd` and `/dev/accel/accel0` are `root:render`** with a logind ACL that grants the active desktop session. That is why GPU and NPU access work at the desk and then fail over SSH, in containers, and from system services. The fix is to add the account to `render` and `video`, which the ROCm setup does. See [ROCm](03-rocm.md).

**The two ASUS platform interfaces disagree.** `/sys/class/firmware-attributes/asus-armoury/attributes/ppt_*` reads stale values; `/sys/devices/platform/asus-nb-wmi/ppt_*` is authoritative. Trusting the first produced a false diagnosis of a TDP regression. See [ASUS hardware](10-asus-hardware.md).

**The MT7925 defaults to power save**, which on this access point produced 86 ms average latency with 65 ms of jitter on a LAN ping. Disabling it is one line and the difference is dramatic. Script `13-wifi-powersave-off.sh`.

**The Wi-Fi card is Wi-Fi 7, but you only get what the access point offers.** On a Wi-Fi 6 access point at 80 MHz this machine associates at Wi-Fi 6 rates and measures around 350 Mbit/s to a wired host. That is the access point's limit, not the card's.

## Peripherals

Logitech Lightspeed receivers work through `hid_logitech_dj` and `hid_logitech_hidpp`. A wireless mouse that "does not work" is usually asleep: the receiver stores the pairing and the kernel creates the input device immediately, but the mouse itself only starts talking when woken. The tell is that `/sys/class/power_supply/hidpp_battery_*` appears only once the mouse is genuinely connected.

For DPI, polling rate, button mapping and LEDs use `piper` (a GUI over `ratbagd`), which writes to the mouse's onboard memory. `solaar` covers Logitech specific features and battery reporting. Both are in the archive.

## Networking

The only ethernet is whatever you plug into USB. A 2.5GbE adapter on the RTL8156B (`r8152`, in tree) negotiated 2500Base-T and measured **293 MB/s (2,343 Mbps)** on an unencrypted HTTP transfer to a 2.5G host, which is the ceiling. An ssh-based test showed only 832 Mbps in one direction, and that was the far end's ssh encryption, not the link; measure with something unencrypted.

**Plugging in wired while Wi-Fi is up on the same subnet breaks routing.** The wired interface gets a DHCP address and DNS but NetworkManager withdraws its routes, logging `conflict detected for IP address ... with host <the Wi-Fi MAC>`. Linux's default ARP settings let any interface answer for any local address, so the Wi-Fi card claims the wired card's new IP and NM's conflict detection believes it. Fix with `arp_ignore=1` and `arp_announce=2`, script `22-arp-multihome.sh`; `nmcli connection modify <wired> ipv4.dad-timeout 0` is the no-root workaround. Existing TCP connections stay on the interface they started on, so a download in flight stays on Wi-Fi until it finishes.

10GbE adapters on the AQC113 chipset work through the in tree `atlantic` driver but need a USB4 port, not the Type-A one, and the Thunderbolt security level of `user` means the device must be authorised once with `bolt` (installed and running by default on Ubuntu) before it appears.
