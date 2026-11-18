# Ubuntu 26.04 on the ASUS ROG Flow Z13 128GB (2025) as a local LLM workstation

Everything needed to take an ASUS ROG Flow Z13 GZ302EA (AMD Ryzen AI MAX+ 395, "Strix Halo", 128 GB) from a fresh Ubuntu 26.04 install to a working local inference machine: GPU, NPU, hybrid, speech, image, audio and 3D generation, all reachable from your other devices, with every number in here measured on the actual hardware rather than quoted.

This is a write-up of a real build, including the things that went wrong and why. It is opinionated where the measurements justify it and says so where they do not.

## Headline results

| Model | Size | Active params | Generation | Notes |
|---|---|---|---|---|
| `qwen3-coder:30b-a3b` | 18 GB | 3B (MoE) | **50.8 tok/s** | fastest, feels instant |
| `gpt-oss:120b` | 65 GB | ~5B (MoE) | **31.6 tok/s** | best speed/capability balance |
| `laguna-S-2.1` | 96 GB | unknown | **22.3 tok/s** | largest that fits, 3.6 GiB spare |
| `qwen3.5:122b` | 81 GB | 10B (MoE) | **22.0 tok/s** | most capable |
| `qwen3.8:27b` | 17 GB | 27B (dense) | 10.7 tok/s | dense; 24.6 tok/s with a speculative drafter under [Gufo](docs/14-gufo.md) |
| Halogen `qwen3.8-flash-next` | 115 GiB | unknown | **35.3 tok/s**, 665 tok/s prefill | separate engine, needs the BIOS on Auto; retired |
| Gufo `qwen3.8-flash-next` + MTP | 111 GB | unknown | **33.5 tok/s**, 1,080 tok/s prefill | replaced Halogen, no BIOS change |

Ollama rows are under the 96 GiB carve-out; under Auto they are 10 to 13 percent lower on generation. The same `qwen3-coder` file under llama.cpp Vulkan generates at 67.8 tok/s against Ollama's 42.1 measured the same day.

The single most important finding: **generation speed tracks active parameters, not model size.** The 65 GB MoE model runs three times faster than the 17 GB dense one. See [benchmarks](docs/05-benchmarks.md) and [inference](docs/04-inference.md).

The third, found later: **the engine is a bigger lever than any setting.** Same weights, llama.cpp Vulkan is 61 percent faster than Ollama on a MoE model, and speculative decoding more than doubles a dense one. See [Vulkan](docs/13-vulkan.md) and [Gufo](docs/14-gufo.md).

The second most important: **the BIOS VRAM carve-out is worth about 7 to 9 percent on generation and nothing on prefill.** The machine ran a 96 GiB carve-out for the numbers above, then moved to Auto to run [Halogen](docs/12-halogen.md); the difference is measured in [benchmarks](docs/05-benchmarks.md#carve-out-versus-gtt).

Beyond text: image generation in 8.6 s, music faster than realtime, sound effects, text to speech, transcription with speaker diarisation on the GPU, image to 3D. See [Lemonade](docs/07-lemonade.md) and [speech](docs/08-speech.md).

## What works out of the box

Ubuntu 26.04 ships kernel 7.0, which supports this hardware in tree. **No DKMS, no vendor drivers, no out of tree modules.** From a clean install: GPU, Wi-Fi 7, Bluetooth, touchscreen and stylus, detachable keyboard, auto rotate, camera, audio, the NPU, and ASUS platform control (TDP, fans, battery limit) all work. See [hardware](docs/01-hardware.md).

## Documentation

| | |
|---|---|
| [01 Hardware](docs/01-hardware.md) | The machine, what works untouched, the BIOS memory split and why it matters |
| [02 Base install](docs/02-base-install.md) | The community setup script, the four bugs found in it, and the patches |
| [03 ROCm](docs/03-rocm.md) | ROCm on 26.04: which repo, why the archive version, the group membership trap |
| [04 Inference](docs/04-inference.md) | Ollama configuration, model selection, the MoE argument in detail |
| [05 Benchmarks](docs/05-benchmarks.md) | Methodology including the prompt cache trap, every measurement, tuning that did nothing |
| [06 NPU](docs/06-npu.md) | FastFlowLM, the memlock blocker, NPU measured against GPU, hybrid HRX |
| [07 Lemonade](docs/07-lemonade.md) | One endpoint for everything: 15 backends, PPA pinning, API mappings, memory |
| [08 Speech](docs/08-speech.md) | Transcription plus diarisation on AMD, and why not WhisperX |
| [09 Remote access](docs/09-remote-access.md) | Tailscale only, loopback everywhere, and Ollama's 403 |
| [10 ASUS hardware](docs/10-asus-hardware.md) | z13ctl, TDP profiles, why custom fan curves are worse, battery persistence |
| [11 Gotchas](docs/11-gotchas.md) | Everything that cost time, in one place |
| [12 Halogen](docs/12-halogen.md) | A second engine for the biggest model: the BIOS trade it forces, measured against Ollama, two benchmark traps. Retired in favour of Gufo |
| [13 Vulkan](docs/13-vulkan.md) | llama.cpp Vulkan against Ollama on identical weights, the settings that matter, Ollama files llama.cpp will not load |
| [14 Gufo](docs/14-gufo.md) | The engine that replaced Halogen, and speculative decoding (MTP, DFlash2, DSpark) on three model families |
| [15 ComfyUI](docs/15-comfyui.md) | Image generation on gfx1151, the MIOpen segfault and its fix, Qwen Image 2.1 timings |
| [16 Living with it](docs/16-living-with-it.md) | Sleep that does not wake, USB4 dock video, SD card automount and suspend, the 2 TB SSD swap, `iommu=pt` |
| [CREDITS](CREDITS.md) | The people whose work this stands on |

## Scripts

Numbered scripts in [`scripts/`](scripts/) reproduce the build. Each is idempotent, backs up what it modifies, and prints what it did. They have had hostnames, addresses and tailnet names replaced with placeholders like `<tailnet>` and `<hostname>`. Read them before running them; several need root.

[`halogen/docker-compose.yml`](halogen/docker-compose.yml) is the Docker adaptation of the podman-targeted Halogen server.

`patches/llm.sh.patch` is the diff against the upstream installer's LLM module, covering the bugs described in [base install](docs/02-base-install.md).

## The machine

| | |
|---|---|
| Model | ASUS ROG Flow Z13 GZ302EA (2025) |
| APU | AMD Ryzen AI MAX+ 395, Strix Halo, 16 cores / 32 threads |
| GPU | Radeon 8060S, `gfx1151`, 40 CUs |
| NPU | AMD XDNA2, `RyzenAI-npu5`, 50 TOPS |
| Memory | 128 GB LPDDR5X-8000, ~256 GB/s |
| OS | Ubuntu 26.04.1 LTS, kernel 7.0.0-31-generic |

## Honesty about scope

This documents one machine and one distro version: about two days of build, then two months of daily use (docs 13 to 16). Measurements are from that hardware and that software on those dates. Several conclusions contradict things published elsewhere, and where that happens the measurement and the method are given so you can check. Two claims made along the way were later found wrong and corrected; both corrections are recorded rather than erased.

## Licence

MIT. See [LICENSE](LICENSE).
