# 04. Inference: Ollama, llama.cpp and choosing models

## Why active parameters are the only number that matters

Strix Halo has 128 GB of unified memory on a ~256 GB/s bus, shared between CPU and GPU. There is no separate VRAM with its own bandwidth. Every byte the GPU reads competes with everything else.

Token generation is memory bandwidth bound. For each token, the model must read every weight that participates in producing that token. So, to a first approximation:

```
tokens per second  ≈  effective bandwidth  ÷  bytes read per token
```

A **dense** model reads all of its weights for every token. A 27B model at 4 bit quantisation is about 17 GB, so every token costs a 17 GB read.

A **mixture of experts** (MoE) model routes each token through a small subset of its weights, the "active" parameters. A 122B model with 10B active reads roughly 10B parameters' worth per token regardless of the other 112B sitting in memory. A 30B model with 3B active reads about 3B.

That is why, measured on this machine:

| Model | On disk | Active | Generation |
|---|---|---|---|
| `qwen3-coder:30b-a3b` | 18 GB | 3B | 50.83 tok/s |
| `gpt-oss:120b` | 65 GB | ~5B | 31.58 tok/s |
| `laguna-S-2.1` | 96 GB | unknown | 22.30 tok/s |
| `qwen3.5:122b` | 81 GB | 10B | 21.95 tok/s |
| `qwen3.8:27b` | 17 GB | 27B dense | 10.67 tok/s |

The 65 GB model runs three times faster than the 17 GB one. Size on disk is close to irrelevant. **Active parameter count is the whole story.**

The relationship is sublinear. Working back from the measurements, effective bandwidth utilisation is roughly 76 GB/s at 3B active, 110 GB/s at 10B, and 189 GB/s for the dense 27B. Scattered expert reads do not stream as efficiently as a dense sequential read, so MoE routing overhead dominates when the active set is small. Nothing here saturates the 256 GB/s bus.

The practical rule: **on this hardware, do not run dense models above about 30B**. A dense 70B would read roughly 40 GB per token and land in low single digit tokens per second regardless of quantisation. A 122B MoE with 10B active fits in the same VRAM and runs four times faster.

## Model selection

With 96 GiB of VRAM, fit is rarely the constraint. Active parameters and capability are. Under the Auto split the GTT cap of 61 GiB becomes the constraint for the two largest models until `gttsize` is raised; see [hardware](01-hardware.md).

| Use | Model | Why |
|---|---|---|
| **Default** | `gpt-oss:120b` | 31.6 tok/s at 65 GB. Faster than the 122B by 44 percent while using 16 GB less. |
| **Fast interactive, coding** | `qwen3-coder:30b-a3b` | 50.8 tok/s and 822 tok/s prefill. The only one that feels instant. At 3B active it is noticeably less capable. |
| **Maximum capability** | `qwen3.5:122b` | 22.0 tok/s. Slowest of the useful set, most capable. |
| **Avoid** | `qwen3.8:27b` | Dense. 10.7 tok/s, three times slower than `gpt-oss:120b` and less capable. Only sensible on a VRAM constrained machine, which this is not. |

Too large for 96 GiB: `qwen3-coder:480b` (290 GB), `qwen3:235b` (142 GB), and the current GLM, MiniMax and DeepSeek flagships.

A caveat on `gpt-oss:120b`: one Strix Halo benchmark source noted quality issues with tool calling, and in use it was seen to leak its reasoning scaffolding and to argue that Ubuntu 26.04 did not exist. It is fast. It is not always good. `qwen3.5:122b` is the fallback when output quality matters more than speed.

## Ollama configuration

`/etc/systemd/system/ollama.service.d/strix-halo.conf`:

```ini
[Service]
Environment="OLLAMA_CONTEXT_LENGTH=32768"
Environment="OLLAMA_FLASH_ATTENTION=1"
Environment="OLLAMA_KEEP_ALIVE=30m"
Environment="OLLAMA_ORIGINS=https://<hostname>.<tailnet>.ts.net,https://<hostname>.<tailnet>.ts.net:11434,http://localhost,http://localhost:*,http://127.0.0.1,http://127.0.0.1:*"
Environment="HIP_VISIBLE_DEVICES=0"
Environment="GPU_MAX_HW_QUEUES=8"
Environment="OLLAMA_HOST=127.0.0.1"
```

Each line has a reason:

**`OLLAMA_CONTEXT_LENGTH=32768`.** Ollama sizes its default `num_ctx` from total VRAM. With 96 GiB it chose **262144**. An 81 GB model plus a 256K token KV cache does not fit, so it would either fail or spill into 15 GiB of GTT and crawl. 32K leaves comfortable headroom for the largest model and is plenty for chat. Raise it per request if you need more.

**`OLLAMA_FLASH_ATTENTION=1`.** Harmless and kept. It did **not** produce a measurable speedup here; see [benchmarks](05-benchmarks.md).

**`OLLAMA_KEEP_ALIVE=30m`.** The 5 minute default meant a 22 to 29 second reload on the first message after any quiet spell, which on a phone reads as a hang. 30 minutes covers a conversation. `-1` (never unload) is the right call on a rack box but wrong on a tablet, where holding 76 GiB resident keeps the APU out of its deeper idle states.

**`OLLAMA_ORIGINS`.** Only governs CORS. It does not fix the 403 that Ollama returns behind a proxy; see [remote access](09-remote-access.md).

**`OLLAMA_HOST=127.0.0.1`.** Loopback only. The installer sets `0.0.0.0`. See [base install](02-base-install.md).

**No `HSA_OVERRIDE_GFX_VERSION`.** Its absence is deliberate and correct. See [ROCm](03-rocm.md).

**`OLLAMA_KV_CACHE_TYPE=q8_0` was tried and reverted.** It halves KV memory at a small quality cost on long contexts. Measured, it gave no speed benefit, and with 96 GiB the memory saving is not needed at 32K context. Not worth the quality trade.

## Ollama's own log tells you what it decided

```bash
journalctl -u ollama -b | grep -iE "inference compute|library="
```

Look for:

```
inference compute ... library=ROCm compute=gfx1151 ... total="96.0 GiB" available="95.8 GiB"
```

`library=ROCm` and `compute=gfx1151` confirm the GPU path with native ISA detection. If you see `compute=gfx1100`, the override is set somewhere. Ollama also enumerates the GPU under Vulkan and then drops it as a duplicate iGPU unless `OLLAMA_IGPU_ENABLE=1` is set; that is normal.

## Vulkan versus ROCm

Ollama uses ROCm. llama.cpp is installed separately as the Vulkan build. Published measurements on identical hardware show Vulkan ahead on generation and ROCm ahead on prompt processing:

| Model | ROCm gen | Vulkan gen | ROCm prefill | Vulkan prefill |
|---|---|---|---|---|
| Qwen3.5-122B-A10B | 21.3 | 22.9 | 523 | 374 |
| Qwen3-Coder-30B-A3B | 73.7 | 97.7 | 1344 | 1115 |

Source: the [Soot / Silicon Vulkan vs ROCm comparison](https://www.soothill.io/blog/2026/08/03/llamacpp-vulkan-vs-rocm-strix-halo/), which is a careful piece of work. This build's own Ollama/ROCm measurement of 21.95 tok/s on the 122B lines up almost exactly with their 21.3, which is reassuring for both.

If generation speed on a small MoE is what you care about, the Vulkan llama.cpp build may be worth an A/B. It was not chased here because the ROCm path was already tuned and measured.

## Memory headroom

```bash
cat /sys/class/drm/card1/device/mem_info_vram_used   # expect: about the model size
cat /sys/class/drm/card1/device/mem_info_gtt_used    # expect: 0 under a carve-out, the model size under Auto
```

With `qwen3.5:122b` resident under the carve-out: 76 to 78 GiB in VRAM, under 0.2 GiB in GTT. That is the healthy state. `amdgpu_top` shows the same live.

`laguna-S-2.1` at 96 GB is the largest model that fits: 92.4 GiB in VRAM with 0.1 GiB GTT at 32K context, leaving 3.6 GiB. Do not raise `num_ctx` on it; that headroom belongs to the KV cache and anything more spills into GTT.
