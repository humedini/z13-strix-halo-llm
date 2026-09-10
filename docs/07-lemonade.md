# 07. Lemonade Server

## What it is

[Lemonade](https://lemonade-server.ai) is AMD's local inference server: one OpenAI compatible endpoint on port 13305 that routes to the GPU, the NPU, or a hybrid of both, and covers far more than text. Version 11.9.0 at time of writing. It is what turned this machine from "runs LLMs" into "generates images, music, sound, speech, transcripts and 3D models from one API".

## Install, and pin the PPA

Ubuntu packages come from `ppa:lemonade-team/stable`, which has a native `resolute` (26.04) build:

```bash
sudo add-apt-repository ppa:lemonade-team/stable
sudo apt install lemonade-server
```

**Do not stop there.** The same PPA ships `amdxdna-dkms` and XRT 2.25.0. Neither is wanted: `amdxdna` is already in tree on kernel 7.0 and working, and FastFlowLM is validated against the archive's XRT 2.21.75. Installing a DKMS driver beside a working in tree one, or silently upgrading XRT under a working stack, is how this breaks a week later.

Script `17-lemonade-server.sh` pins the PPA so only Lemonade comes from it:

```
Package: *
Pin: release o=LP-PPA-lemonade-team-stable
Pin-Priority: 1

Package: lemonade-server lemonade-desktop
Pin: release o=LP-PPA-lemonade-team-stable
Pin-Priority: 700
```

and verifies after installing that `amdgpu-dkms` did not arrive and `libxrt2` is still the archive version. `lemonade-server` depends on neither, so nothing is lost by the pin.

## What the packaging gets right

`lemond.service` runs as a dedicated `lemonade` user that the package already places in the `render` group, so it reaches `/dev/accel/accel0` with no intervention. It inherits `DefaultLimitMEMLOCK=infinity` from the systemd drop-in. It binds `127.0.0.1:13305` and `[::1]:13305` only. All three of those are things that usually need fixing by hand; here they did not.

## Two interfaces, one server

The **web UI** is at `http://127.0.0.1:13305` and needs nothing installed. `lemonade run <model>` opens it with that model loaded. There is also `apt install lemonade-desktop`, a native window with a tray icon around the same interface. It adds nothing functionally.

The CLI, `lemonade`, is an HTTP client to the server: `backends`, `pull`, `load`, `unload`, `pin`, `config`, `bench` and so on.

## Backends installed

```bash
lemonade backends                       # what is available
lemonade backends install flm:npu       # install one
```

| Recipe | Backend | Version | Purpose |
|---|---|---|---|
| `llamacpp` | rocm / vulkan | b10711 / b10723 | LLM on GPU |
| `flm` | npu | v1.0.3 | LLM on NPU |
| `llamacpp-hrx` | hrx | hrx-b59 | hybrid NPU + GPU, experimental |
| `vllm` | rocm | 0.20.1-rocm7.12.0-gfx1151 | production serving |
| `whispercpp` | rocm / vulkan | v1.8.4 | transcription |
| `moonshine` | cpu | 0.0.62 | streaming ASR |
| `kokoro` | cpu | b17 | text to speech |
| `openmoss` | rocm | v0.3.0 | TTS and sound effects |
| `sd-cpp` | rocm | master-827 | Stable Diffusion |
| `thenoise` | rocm | 0.4.1 | Anima image models |
| `acestep` | rocm | v0.1.1 | music generation |
| `thinksound` | rocm | v0.1.2 | sound effects |
| `trellis` | rocm | v0.4.3 | 3D assets |
| `ds4` | rocm | b0001 | DeepSeek V4 Flash |
| `onnxruntime` | cpu | 0.3.7 | ONNX models |

Several of these are built for this exact silicon. The vLLM, whisper, sd-cpp and ds4 packages are `gfx1151` specific, and `llamacpp:rocm` pulls a TheRock `gfx1151` distribution alongside it.

## Everything measured

| Capability | Model | Result |
|---|---|---|
| Image generation | SDXL-Turbo | 512x512 in **8.6 s** |
| Music | ACE-Step-Music | 30 s of audio in **21.5 s**, faster than realtime |
| Sound effects | ThinkSound-SFX | 9 s of audio in **9.8 s** |
| Text to speech | MOSS-TTS-Local | 4.7 s of audio in **9.9 s** |
| Text to speech | kokoro-v1 | verified |
| Streaming ASR | Moonshine-Small | correct transcript |
| Transcription | Whisper-Large-v3-Turbo | 12 accurate timestamped segments |
| Image to 3D | TRELLIS-3D | **210 s**, 79,811 vertices, 143,958 triangles, textured glTF |
| Upscaling | RealESRGAN-x4plus | **does not work**, see below |

The image test is worth describing. The prompt was "a detachable-keyboard tablet computer on a wooden desk, warm evening light, shallow depth of field, photographic", and SDXL-Turbo produced something close to the machine that generated it, in under nine seconds on an integrated GPU.

## API endpoints

Everything is under `/api/v1/` and OpenAI compatible where a convention exists:

```
chat/completions   responses   embeddings
images/generations   images/edits
audio/speech   audio/transcriptions   audio/generations
3d/generations
```

Two mappings are not guessable and cost time:

**Sound effects and music go to `audio/generations`** with a `prompt` field. Sending a non-TTS model to `audio/speech` returns `model_not_applicable`. The response is raw audio bytes, not JSON.

**`3d/generations` requires a base64 `image` field.** TRELLIS is image to 3D, not text to 3D. Generate an image with `sd-cpp` first, then feed it in. The response is raw `model/gltf-binary`; write the bytes straight to a `.glb`. A JSON parser will choke on it.

### RealESRGAN

Loading it fails: `sd-server` exits with code 1, because RealESRGAN is an upscaler weight rather than a diffusion model and cannot be loaded standalone. Passing `upscale_model` to `images/generations` is silently ignored. It may be reachable from the web UI's image controls; it is not reachable programmatically.

## Memory: unload after a session

Each backend runs a persistent server process, roughly 0.6 to 2.3 GB each, and they accumulate. After testing image, music, sound effects and 3D in one session, four servers held 4.7 GB with none in use, leaving under 1 GB genuinely free on a 30 GiB system.

```bash
lemonade unload
```

reaps them properly and returned the full 4.7 GB. This is housekeeping, not a leak. `max_loaded_models` is 1 by default but does not appear to evict across different recipes.

That 30 GiB matters here more than on a typical machine; it is the cost of the 96 GiB VRAM split. See [hardware](01-hardware.md).

## Pinning

```bash
lemonade pin Whisper-Large-v3-Turbo
```

keeps a model resident through the eviction that `max_loaded_models=1` would otherwise cause. `whisper-server` is 95 MB resident, cheap to leave warm. Worth doing for anything you use constantly.

## Relationship to Ollama

Lemonade keeps its own model store and runs as the `lemonade` user, which cannot read your home directory. It will not reuse Ollama's models. Both are kept: Ollama holds the large GPU models and is the tuned, benchmarked path; Lemonade provides the NPU, the hybrid backend, and everything that is not text generation.

Duplicating the large models into Lemonade would cost close to 200 GB and gain nothing. If a single endpoint is wanted, `lemonade cloud install` can register Ollama as an OpenAI compatible provider so Lemonade fronts both without copying anything.

## No authentication

Lemonade has no login. On loopback that is fine. Published over a tailnet it means any device there can load models, run inference and change configuration. Set a key with `lemonade config set api_key=<key>` if that matters to you. See [remote access](09-remote-access.md).

## Models not pulled, deliberately

vLLM is installed with nothing loaded: its value is high concurrency serving, and this is a single user machine where Ollama already runs the same model shapes. `DeepSeek-V4-Flash-IQ2XXS-DS4` would fit at 81 GB but uses aggressive 2 bit quantisation on an unproven backend. Both are one `lemonade pull` away if the situation changes.
