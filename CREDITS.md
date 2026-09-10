# Credits

This build stands on a lot of other people's work. Where something here was learned from someone else, this is where it came from.

## The setup script and its ecosystem

**[th3cavalry/strix-halo-linux-setup](https://github.com/th3cavalry/strix-halo-linux-setup)** by th3cavalry. The starting point. It installed the control layer, Ollama, llama.cpp and Open WebUI, and its `kernel-compat.sh` is a useful map of which fixes matter on which kernel. The bugs documented in [base install](docs/02-base-install.md) are offered in the spirit of making it better, and may already be fixed upstream by the time you read this. v6.8.0, commit `4a05828`.

**[dahui/z13ctl](https://github.com/dahui/z13ctl)** by dahui. The hardware control tool for this exact machine: RGB, TDP, fan curves, profiles, battery limit, all rootless after a udev setup. Its `--help` text is unusually good and taught me most of what is in [ASUS hardware](docs/10-asus-hardware.md), including the documented reason custom curves get discarded and the mandatory fan floor above 75 W.

**[seerge/g-helper](https://github.com/seerge/g-helper)** by seerge. The Windows tool for ASUS ROG hardware whose protocol reverse-engineering z13ctl builds on.

**[TechnoDaimon/Strix-Halo-Control](https://github.com/TechnoDaimon/Strix-Halo-Control)** and **[kyuz0/amd-strix-halo-toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes)**, both referenced by the setup script as GUI inspiration and containerised AI toolboxes respectively.

## Inference engines

**[Ollama](https://github.com/ollama/ollama)**. The GPU inference path. Its log line `inference compute ... compute=gfx1151` was the definitive proof that `HSA_OVERRIDE_GFX_VERSION` was wrong.

**[ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp)** and **[ggml-org/whisper.cpp](https://github.com/ggml-org/whisper.cpp)** by Georgi Gerganov and contributors. Underneath Ollama, Lemonade's GPU backends, and the transcription stage of the speech pipeline. The Vulkan and ROCm builds are what make AMD viable for this at all.

**[ROCm/FastFlowLM](https://github.com/ROCm/FastFlowLM)**, originally by dahui and now under AMD's ROCm organisation. The only thing that runs LLMs on the XDNA2 NPU on Linux. Its `flm validate` command is the sole clear reporter of the memlock problem.

**[Lemonade](https://lemonade-server.ai)** by AMD. Fifteen backends behind one API, packaged well enough that the service user, group membership and memlock inheritance all came right without intervention. The HRX backend is theirs too, and the fact that it is experimental is stated plainly in their own docs.

**[Open WebUI](https://github.com/open-webui/open-webui)**. The chat interface.

**[peonist-ai/halogen-flash-server](https://github.com/peonist-ai/halogen-flash-server)** by peonist-ai. A from-scratch inference server for Strix Halo with its own weight format, multi-token prediction and an honest note in its own log that it wants the machine to itself. Its `serve_api` timing line, which reports prefill and decode separately, is what made the benchmark here trustworthy.

## Speech

**[pyannote.audio](https://github.com/pyannote/pyannote-audio)** by Hervé Bredin and contributors. Speaker diarisation, and its documented in-memory audio workaround is what made it run here without torchcodec.

**[PyTorch](https://pytorch.org)** for shipping ROCm wheels including `cp314`, which is why Python 3.14 was not a blocker.

**[OpenAI Whisper](https://github.com/openai/whisper)** for the models, and **[Moonshine](https://github.com/usefulsensors/moonshine)** by Useful Sensors for streaming ASR.

## Measurement and comparison

**[Soot / Silicon: llama.cpp Vulkan vs ROCm on Strix Halo](https://www.soothill.io/blog/2026/08/03/llamacpp-vulkan-vs-rocm-strix-halo/)**. Careful, reproducible numbers on the same silicon. This build's independent ROCm measurement landed within 3 percent of theirs, which is the kind of agreement that makes both more trustworthy.

**[hogeheer499/strix-halo-guide](https://github.com/hogeheer499-commits/strix-halo-guide)** for an evidence-first approach to Strix Halo benchmarking that shaped the methodology section.

**[Shoresh613/rocm-strix-halo](https://github.com/Shoresh613/rocm-strix-halo)** for an early guide to ROCm on this hardware.

**[Umio-Yasuno/amdgpu_top](https://github.com/Umio-Yasuno/amdgpu_top)** for the VRAM versus GTT view that is the single most useful monitoring signal on a unified memory machine.

**[m-bain/whisperX](https://github.com/m-bain/whisperX)** and its ROCm discussion thread, for making clear exactly why it would not accelerate here, which is what led to the whisper.cpp plus pyannote approach instead.

## AMD documentation

The [ROCm on Ryzen install guide](https://rocm.docs.amd.com/projects/radeon-ryzen/en/latest/) for the `render`/`video` group requirement and the `--no-dkms` rule, and the [ROCm 10 release notes](https://rocm.docs.amd.com/en/latest/) for the `stable.repo.amd.com` move that corrected an earlier mistake here.

## Ubuntu

Canonical, for shipping a complete ROCm stack and the `amdxdna` NPU driver in the 26.04 archive. That is why this build needed nothing from a vendor repository.

## The people on forums

Several specific findings came from individual forum and issue-tracker posts: the Ollama `Host` header behaviour behind Tailscale serve, the `BootDriverFlags` registry fix for booting Windows from USB storage, and the Open WebUI API key visibility quirk. Those threads are linked from the relevant pages where they were the source.
