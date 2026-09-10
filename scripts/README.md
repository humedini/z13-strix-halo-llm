# Scripts

The numbered scripts reproduce the build in order. Each is idempotent, backs up anything it modifies, and prints what it did. **Read them before running them.** Most need root; the ones that do say so.

Placeholders have replaced anything specific to the original machine:

| Placeholder | Meaning |
|---|---|
| `<hostname>` | the machine's hostname |
| `<tailnet>` | your tailnet's MagicDNS suffix, e.g. `tailXXXXXX` |
| `<tailscale-ip>` | the machine's Tailscale IPv4, `100.x.y.z` |
| `<user>` | your username |
| `<lan-host>`, `<lan-ip>` | LAN addresses used only in comments and tests |

Search for `<` in any script to find what needs filling in. Several scripts derive these at runtime from `tailscale status` and need nothing.

## In order

| Script | Root | Purpose |
|---|---|---|
| `01-prep.sh` | yes | git, build-essential, mesa-utils, vulkan-tools, lm-sensors, rocminfo. The community installer assumes the first two exist. |
| `03-postfix.sh` | yes | Strips `HSA_OVERRIDE_GFX_VERSION` from the profile script and the Ollama drop-in, binds Ollama to loopback. Run after the community installer. |
| `04-verify.sh` | no | Whole-stack verification. Reads both the stale and live TDP attributes and labels them. |
| `05-tailscale-install.sh` | yes | Tailscale from the official repo's `resolute` channel. |
| `06-lockdown-and-serve.sh` | yes | Open WebUI to host networking on loopback, tailnet CORS origin for Ollama, publishes both via `tailscale serve`. Falls back to a published-port container if the image ignores `HOST`. |
| `07-rocm-complete.sh` | yes | Full ROCm from the Ubuntu archive plus `render` and `video` groups. Warns if `amdgpu-dkms` appears. Reboot after. |
| `08-ollama-proxy.sh` | yes | nginx loopback shim that rewrites the `Host` header so Ollama stops returning 403 behind Tailscale serve. Removes nginx's `0.0.0.0:80` default site. |
| `09-ollama-context.sh` | yes | Pins `OLLAMA_CONTEXT_LENGTH`. Argument, default 32768. Also clears any transient `systemctl set-environment` override that would shadow it. |
| `10-z13ctl-setup.sh` | yes | udev rules and boot permissions service so z13ctl works rootless, plus the 80% charge cap. |
| `11-monitoring.sh` | yes | `nvtop`, `btop`, and `amdgpu_top` from its upstream `.deb`, version resolved live. |
| `12-battery-limit-persist.sh` | yes | systemd unit that reapplies the charge cap on boot and resume, waiting for the late-created attribute. Argument, default 80. |
| `13-wifi-powersave-off.sh` | yes | Disables MT7925 power save on the active connection and as the NetworkManager default. |
| `14-ollama-tuning.sh` | yes | Flash attention and keep-alive. Argument for keep-alive, default 30m. The q8_0 KV cache it also sets was measured as no benefit and later removed by hand; see the benchmarks doc. |
| `15-npu-fastflowlm.sh` | yes | FastFlowLM `.deb` plus XRT from the archive. Expects the `.deb` beside it; prints the download URL if missing. |
| `16-npu-memlock.sh` | yes | Raises memlock via both PAM limits and systemd defaults. Log out after. |
| `17-lemonade-server.sh` | yes | Lemonade from its PPA, with the PPA pinned so `amdxdna-dkms` and the newer XRT cannot arrive. Verifies after. |
| `18-whisper-diarisation-prereqs.sh` | yes | ffmpeg and Python venv tooling. The venv itself is built by hand; see the speech doc. |
| `19-lemonade-tailnet.sh` | yes | Publishes Lemonade via `tailscale serve`. No shim needed; Lemonade accepts any `Host`. |
| `20-ssh-server.sh` | yes | sshd bound to the Tailscale addresses and loopback, never `0.0.0.0`. |
| `21-windows-usb-boot-prep.sh` | yes | Prepares a Windows NVMe in a USB enclosure to boot, by editing its SYSTEM hive offline. Untested at time of writing; the enclosure had not arrived. |
| `22-arp-multihome.sh` | yes | `arp_ignore=1` / `arp_announce=2` sysctls so Wi-Fi and wired on one subnet stop answering ARP for each other. Fixes NM withdrawing the wired interface's routes. |
| `23-halogen-tailnet.sh` | yes | Publishes Halogen's API via `tailscale serve` on 8731, after checking it accepts a foreign `Host` header. |
| `24-gttsize.sh` | yes | Adds `amdgpu.gttsize=108544` plus `ttm.pages_limit` and `ttm.page_pool_size` to the kernel command line so the GPU can borrow 106 GiB under the Auto split. Both limits default to half of RAM and ROCm honours the lower. Reboot required. |

Script `02` does not exist; that number was the community installer itself.

## Benchmark harnesses

| Script | Purpose |
|---|---|
| `bench-model.py` | Ollama. Unique prompt per run to defeat the cache, 400 token generations, median of three. `bench-model.py <model> [runs] [num_predict]` |
| `bench-flm.py` | FastFlowLM on the NPU, using its own reported speeds. Needs `flm serve <model> --port 11436`. |
| `bench-lemonade.py` | Lemonade, using llama.cpp's `timings` block. Port 13305. |
| `bench-openai.py` | Any OpenAI-compatible server, streaming, with time to first token. Counts `reasoning_content` as well as `content`, which thinking models need. `bench-openai.py <base-url> <model> [runs]` |
| `bench-npu-vs-gpu.sh` | Wraps any of the above and samples APU package power once a second. `bench-npu-vs-gpu.sh LABEL <command...>` |

## Speech

| Script | Purpose |
|---|---|
| `diarise.py` | Transcribe via Lemonade, diarise via pyannote on ROCm, merge. Run with the venv's Python. `diarise.py AUDIO [--speakers N] [--model M] [--json OUT]` |
