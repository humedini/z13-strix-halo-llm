# 11. Gotchas, consolidated

Every one of these cost time. Each is explained in full elsewhere; this is the index.

## Measurement

- **Ollama caches prompts.** Identical repeated benchmarks measure the cache, not the model, and report a phantom twenty-fold prefill improvement. Unique prompt per run. [Benchmarks](05-benchmarks.md)
- **Short generations distort tok/s.** Fixed overhead dominates a 30 token answer. Ask for 400. [Benchmarks](05-benchmarks.md)
- **Single measurements cannot support small claims.** Run to run spread is ~2.4 tok/s. Median of three. [Benchmarks](05-benchmarks.md)
- **CUDA tuning does not transfer to ROCm.** Flash attention plus q8_0 KV cache, a large win on NVIDIA, changed nothing here. [Benchmarks](05-benchmarks.md)
- **The `asus-armoury` TDP attributes read stale.** Use `/sys/devices/platform/asus-nb-wmi/ppt_*`. [ASUS hardware](10-asus-hardware.md)

## Install

- **The community installer aborts at section 3** on a filename mismatch, before the AI section runs. Symlink the module names. [Base install](02-base-install.md)
- **Installing `rocminfo` makes the installer's LLM module crash** on an unguarded grep under `pipefail`. Patch first. [Base install](02-base-install.md)
- **The installer sets `HSA_OVERRIDE_GFX_VERSION=11.0.0`**, forcing gfx1100 kernels on gfx1151 hardware, in two files. Remove it from both. [Base install](02-base-install.md)
- **llama.cpp's `releases/latest` has no binaries.** Use the `bNNNN` build releases from `ggml-org`. [Base install](02-base-install.md)
- **`git` and `build-essential` are not on a fresh desktop install.** The installer assumes they are. [Base install](02-base-install.md)
- **`~` inside a sudo script is `/root`.** Resolve paths relative to the script. Cost one failed run.
- **`pkill -f "pattern"` matches the shell running it** if the pattern is in the command line. Killed the shell twice. Use `pgrep -x` or kill by PID.
- **`!` at the start of a line in bash is logical NOT**, not history, not a Claude Code prefix. `! install -d ... && printf ...` creates the directory and then stops, because `! install` succeeded-inverted-to-failure ends the `&&` chain.

## ROCm and NPU

- **`repo.radeon.com` has no 26.04 build. `stable.repo.amd.com` does.** An earlier conclusion that AMD had no 26.04 support was wrong. [ROCm](03-rocm.md)
- **`/dev/kfd` works at the desk and fails over SSH** until you are in `render` and `video`. Logind ACLs grant only the seat session. [ROCm](03-rocm.md)
- **The NPU is blocked by an 8 MB memlock default.** Raise PAM limits *and* systemd `DefaultLimitMEMLOCK`, then log out. Only `flm validate` reports it. [NPU](06-npu.md)
- **The NPU is not faster to first token and not more efficient per token**, whatever the marketing says. Measured. [NPU](06-npu.md)
- **HRX hybrid dies above ~500 prompt tokens** on an unimplemented `GET_ROWS` op, after being 62 percent faster on short ones. [NPU](06-npu.md)
- **The Lemonade PPA ships `amdxdna-dkms` and a newer XRT.** Pin it to Lemonade packages only. [Lemonade](07-lemonade.md)

## Networking

- **The installer binds Ollama and Open WebUI to `0.0.0.0`.** On a tablet that is every café's Wi-Fi. Loopback plus Tailscale. [Remote access](09-remote-access.md)
- **Ollama returns 403 behind any proxy** on the `Host` header. `OLLAMA_ORIGINS` does not help. nginx shim. [Remote access](09-remote-access.md)
- **Installing nginx opens `0.0.0.0:80`.** Delete the default site. [Remote access](09-remote-access.md)
- **Open WebUI keeps its Ollama URL in its database.** Env vars only seed it. Change it in the admin UI. [Remote access](09-remote-access.md)
- **Open WebUI on bridge networking cannot reach Ollama on loopback.** Host networking with `HOST=127.0.0.1`. [Remote access](09-remote-access.md)
- **Open WebUI API keys are hidden twice**: an admin toggle under Authentication, then a collapsed "Show" on the Account page. [Remote access](09-remote-access.md)
- **`https://` must be typed** for tailnet ports other than 443. [Remote access](09-remote-access.md)
- **`sudo ufw enable` cuts off every service** including SSH. Allow `tailscale0` first. [Remote access](09-remote-access.md)
- **MT7925 power save wrecks latency.** 86 ms average on a LAN. One nmcli line. [ASUS hardware](10-asus-hardware.md)
- **A wired adapter on the same subnet as Wi-Fi gets an address but no routes.** Linux's default `arp_ignore=0` lets the Wi-Fi card answer ARP for the wired card's IP; NM sees a "conflict" with its own other MAC and withdraws the routes. `ipv4.dad-timeout 0` on the wired profile is the no-root workaround; `arp_ignore=1` and `arp_announce=2` (script `22-arp-multihome.sh`) is the fix. [Hardware](01-hardware.md)
- **A TCP connection keeps the interface it started on.** Plugging in ethernet mid-download leaves that download on Wi-Fi until it ends. Restart it if it resumes; Ollama pulls do.
- **`curl --interface <ip>` does not force an interface on Linux.** Routing is by destination; the source IP just rides along and replies arrive wherever ARP last pointed. A "Wi-Fi" throughput test measured 2.3 Gbps that way. Use separate subnets or take one interface down.

## Speech

- **WhisperX transcribes on the CPU on AMD.** CTranslate2 has no ROCm backend. whisper.cpp plus pyannote instead. [Speech](08-speech.md)
- **pyannote 4.x: `use_auth_token` became `token`**, and it returns `DiarizeOutput` not `Annotation`. [Speech](08-speech.md)
- **torchcodec does not load.** Pass audio in memory. [Speech](08-speech.md)
- **The NPU whisper backend returns no timestamps.** It cannot diarise. [Speech](08-speech.md)

## Lemonade

- **Sound and music go to `audio/generations`**, not `audio/speech`. [Lemonade](07-lemonade.md)
- **3D needs a base64 `image` and returns raw glTF bytes.** [Lemonade](07-lemonade.md)
- **RealESRGAN cannot be loaded standalone or invoked as a parameter.** [Lemonade](07-lemonade.md)
- **Backend servers accumulate at 0.6 to 2.3 GB each.** `lemonade unload` after a session. [Lemonade](07-lemonade.md)
- **Lemonade has no authentication.** [Lemonade](07-lemonade.md)

## Hardware

- **Custom fan curves are always louder at idle.** The EC ignores PWM 0. Firmware auto reaches 0 RPM; no custom curve does. [ASUS hardware](10-asus-hardware.md)
- **The kernel drops custom fan curves on every profile change**, and only re-applies them if they belong to the active profile. [ASUS hardware](10-asus-hardware.md)
- **`--pl1/--pl2/--pl3` need a base `--set`** or z13ctl prints help and does nothing. [ASUS hardware](10-asus-hardware.md)
- **Battery limit resets on boot and resume.** systemd unit that waits for the late-created attribute. [ASUS hardware](10-asus-hardware.md)
- **Hibernate is off under Secure Boot** by kernel lockdown policy, and no amount of swap changes that. [ASUS hardware](10-asus-hardware.md)
- **GTT is only 15 GiB** with the 96/30 split. If it fills, weights are spilling and everything crawls. Under Auto it is 61 GiB and is where the weights live; the two largest Ollama models then do not fit until `amdgpu.gttsize` **and** `ttm.pages_limit` are raised. Raising only the first changes `mem_info_gtt_total` and nothing else; ROCm takes the lower limit. [Hardware](01-hardware.md)
- **The carve-out is worth 7 to 9 percent on generation, nothing on prefill.** Measured, not assumed. [Hardware](01-hardware.md)
- **A sleeping Lightspeed mouse looks like a broken driver.** The device node exists from the stored pairing; `hidpp_battery_*` appearing is the real "connected" signal. [Hardware](01-hardware.md)
- **A 10GbE Thunderbolt adapter needs the USB4 port and a `bolt` authorisation.** [Hardware](01-hardware.md)

## Halogen

- **It cannot see a VRAM carve-out.** Weights are pinned host RAM. The BIOS has to be on Auto, which is a reboot and a small speed cost for everything else. [Halogen](12-halogen.md)
- **Podman compose needs `group_add` for `render` and `video` under Docker**, or the container cannot open `/dev/kfd`. [Halogen](12-halogen.md)
- **Thinking models stream `reasoning_content` before `content`.** A benchmark that waits for `content` reports zero generation speed. [Halogen](12-halogen.md)
- **Two-request prefill subtraction is defeated by the prefix cache.** Subtracting a `max_tokens=1` run from a full run overstates generation by 40 percent if the prompts share a prefix. [Halogen](12-halogen.md)
- **The health check needs a long `start_period`.** First starts of 2 to 44 minutes are reported upstream; Docker's default 0 s would restart-loop it. [Halogen](12-halogen.md)

## Two conclusions that were wrong and corrected

- **"AMD has no ROCm for Ubuntu 26.04."** Drawn from a 404 on `repo.radeon.com`. AMD had moved to `stable.repo.amd.com`. Corrected in [ROCm](03-rocm.md).
- **"Hybrid NPU+GPU execution does not exist on Linux."** Drawn from `flm` and Ollama each lacking the other's backend. Lemonade 11.9's HRX does exactly that. Corrected in [NPU](06-npu.md).

Both are left in the record rather than erased, because the reasoning that produced them was locally sound and the next person is likely to reproduce it.
