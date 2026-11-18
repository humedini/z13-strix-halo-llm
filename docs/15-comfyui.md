# 15. ComfyUI on gfx1151

[Lemonade](07-lemonade.md) covers quick image generation through `sd-cpp`. For real image workflows, ComfyUI runs directly on the GPU through PyTorch. It works, with one crash to get past first.

## Install

Plain ComfyUI v0.42.0 in its own venv with the ROCm PyTorch wheel, `torch 2.14.0+rocm7.2`, the same one used for [speech](08-speech.md). Nothing gfx1151-specific in the install. Bind it to loopback and publish it the usual way if you want it remotely ([remote access](09-remote-access.md)).

`scripts/comfyui-start.sh` is the launcher used here: it stops any previous instance on the same port, sets the environment below and waits for the API to answer.

## The crash: MIOpen and Conv3d

The first Qwen Image 2.1 **Image Edit** run killed Python outright: a segfault, with apport reporting "python3.14 stopped unexpectedly" and nothing useful in ComfyUI's log. Text to image worked.

The cause is two things together:

- ComfyUI **disables MIOpen on RDNA3 and newer** by default, so convolutions fall back to PyTorch's native implementations.
- PyTorch's native **bf16 Conv3d segfaults on gfx1151**. Qwen3-VL, the text encoder used for image editing, has a 3D convolution in its image patch embedding, which is why only the edit workflow died.

The fix is to turn MIOpen back on, and to stop it searching for the best kernel every time it sees a new shape:

```bash
export COMFYUI_ENABLE_MIOPEN=1
export MIOPEN_FIND_MODE=FAST
```

Without `FAST`, each new image size costs about eight minutes of kernel search before the first step. With it, there is no visible delay.

Other launch flags used: `--disable-mmap --disable-pinned-memory --reserve-vram 4`. Pinned memory gains nothing on unified memory, and the reserve keeps the desktop responsive while a job runs.

## Measured, 2026-10-28

Qwen Image 2.1 in bf16 (the int8 builds used on NVIDIA were not tried on ROCm), with the Qwen3-VL 8B encoder:

| Workflow | Size | Steps | Time |
|---|---|---|---|
| Text to image, first run after start | 1024 x 1024 | 25 | 130 s, 4.2 s per step |
| Image edit | about 1 MP | | 97 s |

It holds about 32 GB of GPU memory, so it cannot run alongside a large LLM such as [Gufo](14-gufo.md) with Flash-Next (85 GiB). Stop one before starting the other.

For video, the same machine was about five times slower than an NVIDIA GB10 system on the same workflow (455 s against 78 s for a 5 second clip). That is the gap between this chip's compute and a dedicated one, not a software problem, and it is why video lives elsewhere.

## API use

If you drive Qwen Image editing through the API rather than the UI, the `TextEncodeQwenImage21` node needs the `vae` input connected, and the sampler's latent must come from that node's second output. Without both, the result is a restyle of the input image rather than an edit of it.

## Attention

Flash and memory-efficient SDPA are already the default on gfx1151 with torch 2.14, so there is nothing to switch on. See [ROCm](03-rocm.md#pytorch-attention-and-rocm-10).
