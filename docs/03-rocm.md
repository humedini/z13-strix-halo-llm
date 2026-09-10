# 03. ROCm on Ubuntu 26.04

## Short version

Use the ROCm in the Ubuntu archive. Add your user to `render` and `video`. Reboot. Done.

```bash
sudo apt install rocm
sudo usermod -a -G render,video $USER
# reboot
```

Script `07-rocm-complete.sh` does exactly this, about 129 packages.

## The repository confusion, in full

AMD's official install guide for Ryzen APUs describes downloading `amdgpu-install` from `repo.radeon.com`. On Ubuntu 26.04, at the time of this build:

- `https://repo.radeon.com/rocm/apt/latest/dists/resolute/Release` returned **404**
- Only `noble` (24.04) existed there

An earlier version of this write-up concluded from that 404 that AMD had no 26.04 support at all, and warned against `repo.radeon.com` entirely. That was **wrong in its conclusion** even though the 404 was real.

AMD had moved to a **new repository host**: `stable.repo.amd.com`. ROCm 10.0.0 is published there with explicit Ubuntu 26.04 support, verified present as `amdrocm10.0` version 10.0.0-4 at `https://stable.repo.amd.com/rocm/core/packages/ubuntu2604/`. AMD's documentation for it states that Ryzen APUs on Ubuntu 26.04 use the inbox kernel driver with no DKMS.

So both of these are true at once:

1. `repo.radeon.com` has nothing for 26.04. Do not force `noble` packages in; that risks libstdc++ and Python ABI conflicts.
2. `stable.repo.amd.com` does have ROCm 10 for 26.04 and it does support `gfx1151`.

## Why this build stays on the archive's ROCm 7.1 anyway

Almost nothing in the working inference stack uses the system ROCm:

| Component | ROCm it actually uses |
|---|---|
| Ollama | bundles its own, `rocm_v7_2` |
| PyTorch (for diarisation) | bundles its own, `2.14.0+rocm7.2` |
| Lemonade `llamacpp:rocm` | bundles TheRock `gfx1151` build 7.14.0 |
| Lemonade whisper, sd-cpp | bundled `rocm-7.14.0` builds |
| Lemonade vLLM | bundled `rocm7.12.0` |
| System ROCm 7.1 | `hipconfig`, `rocminfo`, `rocm-smi`, and anything you compile yourself |

Upgrading system ROCm therefore changes diagnostic tools and future local compilation, not inference performance. Every benchmark in this repository would be unaffected.

There is also a practical trap. AMD's packages are named `amdrocm10.0`, `amdrocm-base` and so on. Ubuntu's are `rocm`, `rocm-dev`. They would **coexist** rather than upgrade cleanly, and two ROCm installations with different `hipconfig` output is exactly the kind of thing that confuses a build six months later.

If you start compiling HIP code locally, revisit this. Otherwise it is a deliberate deferral.

## The group membership trap

This one costs people a lot of time because the symptom is inconsistent.

`/dev/kfd` (and `/dev/accel/accel0` for the NPU) are owned `root:render`, mode 660, with a **logind ACL** that grants access to whichever user owns the active seat session. That means:

- At the desk, logged into GNOME: ROCm works, `rocminfo` shows the GPU, everything is fine
- Over SSH, in a container, from a systemd service: `rocminfo` shows nothing, PyTorch says no GPU, and nothing explains why

The fix is to be in `render` and `video`:

```bash
sudo usermod -a -G render,video $USER
```

and then **log out and back in**, or reboot. Group membership is applied at session creation.

The `ollama` service user gets these groups from its own installer. The `lemonade` service user gets them from its packaging. Your own account does not get them from anything unless you add them.

## Verification

```bash
rocminfo | grep -E "Name:|gfx"
```

Should show `gfx1151` as an agent, plus `amdgcn-amd-amdhsa--gfx1151` and `amdgcn-amd-amdhsa--gfx11-generic` as ISA targets, plus `aie2` for the NPU. That is native gfx1151 support and it is why `HSA_OVERRIDE_GFX_VERSION` must not be set. See [base install](02-base-install.md) for the bug that sets it anyway.

```bash
hipconfig --version      # 7.1.52801 on the archive version
```

## `amd-ttm`

AMD's guide mentions `amd-ttm` for tuning how much system memory the GPU may borrow beyond VRAM. Under the 96 GiB carve-out there is little to borrow; under Auto the same knob matters and is set with `amdgpu.gttsize` instead, see [hardware](01-hardware.md). With 96 GiB of VRAM assigned in BIOS there is little to borrow and only 30 GiB to lend, so it was left at default. If your split is different, it may matter more.

## DKMS

AMD's guide is explicit that Ryzen APUs require the inbox kernel driver and that `amdgpu-dkms` must not be installed. On kernel 7.0 this is satisfied automatically. Script `07-rocm-complete.sh` warns if `amdgpu-dkms` ever appears. So does the Lemonade PPA pinning, since that PPA ships `amdxdna-dkms` which is equally unwanted. See [Lemonade](07-lemonade.md).
