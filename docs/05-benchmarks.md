# 05. Benchmarks and how to not fool yourself

All numbers in this repository were measured on the machine described in [hardware](01-hardware.md), on 2026-09-08, with the harness in `scripts/bench-model.py` unless stated. Methodology first, because two of the traps below very nearly produced published nonsense.

## Methodology

**Unique prompt per run.** Ollama caches prompts. Re-running an identical prompt returns a cached prefill and reports around **5900 tok/s** against a true cold value near 275. That is a twenty-fold phantom improvement, and it nearly went into a comparison table. Every run in the harness embeds a random nonce in the prompt so no two are identical.

**Long generations.** With `num_predict=200` and a short prompt, the model sometimes answered in 30 tokens, and fixed per request overhead distorted the rate badly. The harness asks for a multi paragraph answer and sets `num_predict=400`. Spread dropped from 5.8 tok/s to about 1 tok/s once that was fixed.

**Long prompts.** Prefill on 26 tokens is meaningless. The harness pads to roughly 1,200 to 2,300 prompt tokens.

**Median of three, spread reported.** Generation varies by roughly 2.4 tok/s run to run on this machine. One measurement cannot support a claim of a 10 percent change. Three runs with the spread shown can.

**Cold against cold.** When comparing configurations, compare the first run after a restart against the first run after a restart. Warm runs hit the prompt cache and measure nothing.

**Power sampled alongside.** `scripts/bench-npu-vs-gpu.sh` wraps any benchmark and samples APU package power from the `amdgpu` hwmon `power1_average` once a second, reporting mean and peak.

## The models

| Model | On disk | Active params | Prefill | Generation | Spread |
|---|---|---|---|---|---|
| `qwen3-coder:30b-a3b-q4_K_M` | 18 GB | 3B (MoE) | 822.7 tok/s | **50.83 tok/s** | 1.02 |
| `gpt-oss:120b` | 65 GB | ~5B (MoE) | 288.8 tok/s | **31.58 tok/s** | 0.19 |
| `laguna-S-2.1` | 96 GB | unknown | 294.7 tok/s | **22.30 tok/s** | 0.28 |
| `qwen3.5:122b` | 81 GB | 10B (MoE) | 194.4 tok/s | **21.95 tok/s** | 0.14 |
| `qwen3.8:27b` | 17 GB | 27B (dense) | 221.2 tok/s | **10.67 tok/s** | 0.59 |
| `gpt-oss:20b` | 13 GB | ~4B (MoE) | 1547.6 tok/s | **46.79 tok/s** | 7.12 |
| Halogen `qwen3.8-flash-next` | 115 GiB | unknown | **665 tok/s** | **35.3 tok/s** | 5.1 |

All via Ollama on ROCm under the 96 GiB carve-out, `OLLAMA_CONTEXT_LENGTH=32768`, `OLLAMA_FLASH_ATTENTION=1`, no KV cache quantisation, TDP 70/86/86 W. The Halogen row is a different engine under the Auto split, with its own model; see [Halogen](12-halogen.md) before comparing it to the others.

## Carve-out versus GTT

The same two models, same prompts, same TDP, once with weights in the 96 GiB carve-out and once through GTT under the Auto split. Three runs each, no other load.

| Model | Carve-out generation | GTT generation | Change | Carve-out prefill | GTT prefill |
|---|---|---|---|---|---|
| `qwen3-coder:30b-a3b` | 50.83 tok/s | 46.04 tok/s | −9.4% | 822.7 tok/s | 1266.6 tok/s |
| `gpt-oss:20b` | 46.79 tok/s | 43.47 tok/s | −7.1% | 1547.6 tok/s | 1612.9 tok/s |

Generation is memory-bandwidth-bound and the GTT path costs it under a tenth. Prefill is compute-bound and does not care where the weights are; the GTT prefill numbers being higher is most likely the two weeks of Ollama updates between the runs rather than anything about memory.

An earlier run of the GTT case at the 40/55/55 W quiet profile, with a download in flight, produced 52.5 tok/s on `qwen3-coder:30b-a3b` and 41.4 tok/s on `gpt-oss:20b` at a mean of 39 W. That is generation at least as fast as the 70 W run at half the power, and prefill down about 26 percent. Take it as one data point, not a result, but it fits the bandwidth argument: generation does not need the power, prefill does.

Load times from cold: 22 s for the 27B, 24 s for the 65 GB `gpt-oss:120b`, 30 s for the 81 GB `qwen3.5:122b`. NVMe is not the bottleneck; that is roughly 2.7 GB/s.

## NPU against GPU, identical weights

`gpt-oss:20b`, same model file on both. GPU via Ollama on ROCm, NPU via FastFlowLM. Power is APU package power sampled during the run.

| | GPU | NPU | |
|---|---|---|---|
| Generation | **46.79 tok/s** | 18.96 tok/s | GPU 2.47x faster |
| Prefill | **1547.6 tok/s** | 301.4 tok/s | GPU 5.13x faster |
| Time to first token | ~1.13 s | 6.01 s | GPU 5.3x faster |
| APU power, mean | 63.2 W | **27.1 W** | NPU 2.33x lower |
| APU power, peak | 85.1 W | **31.1 W** | NPU 2.74x lower |
| Tokens per joule | **0.740** | 0.700 | GPU marginally ahead |

Two widely repeated claims did not survive this. The NPU does **not** reach first token sooner; it is 5.3 times slower, because its prefill is weak. And it is **not** more energy efficient per token; it draws less power but is proportionally slower, so the joules per token come out roughly equal with the GPU slightly ahead. The decode ratio of 2.47x did match the published ~2.4x. See [NPU](06-npu.md) for what the NPU is actually good for.

## Concurrent NPU and GPU

Both engines running at once, same model on each:

| | Solo | Concurrent | Change |
|---|---|---|---|
| GPU generation | 46.79 | 42.13 tok/s | -10.0% |
| GPU prefill | 1547.6 | 1177.8 tok/s | -23.9% |
| NPU generation | 18.96 | 18.67 tok/s | -1.5% |
| NPU prefill | 301.4 | 245.7 tok/s | -18.5% |
| NPU time to first token | 6.01 s | 7.92 s | +32% |

Aggregate throughput 60.8 tok/s against 46.8 GPU only, about a 30 percent gain for a 10 percent GPU penalty. The NPU barely notices the GPU; the GPU pays a real cost. Prefill suffers most on both because it is the bandwidth hungry phase and bandwidth is the shared resource. Caveat: the GPU job produced short answers on some runs so the overlap window was imperfect. Throughput figures are sound; treat any combined power number as indicative.

## Hybrid HRX

`Qwen3-30B-A3B-Instruct-2507-HRX` through Lemonade's experimental `llamacpp-hrx` backend, which sends prompt processing to the NPU and generation to the GPU. Short prompts only, because it fails above about 500 tokens; see [NPU](06-npu.md).

| | GPU only | HRX hybrid | NPU only |
|---|---|---|---|
| Generation | 50.83 tok/s | **82.15 tok/s** | 18.96 tok/s |
| Prefill | **822.7 tok/s** | 258.9 tok/s | 301.4 tok/s |
| APU power, mean | ~63 W | 65.4 W | 27.1 W |

62 percent faster generation than GPU only, which is remarkable, and unusable in practice today. The GPU only figure is `qwen3-coder:30b-a3b`, a different model of the same shape, so treat the ratio as indicative.

## Tuning that changed nothing

`OLLAMA_FLASH_ATTENTION=1` with `OLLAMA_KV_CACHE_TYPE=q8_0` is reported as a large prompt eval win on NVIDIA hardware. Measured here on `qwen3.8:27b`, cold run against cold run:

| | Prefill | Generation |
|---|---|---|
| Before | 277.3 tok/s | 15.10 tok/s |
| After | 274.3 tok/s | 16.78, 15.22, 14.34 tok/s across three runs |

Within noise on both. Flash attention on ROCm for gfx1151 does not have the mature kernel it has on CUDA. Flash attention was kept because it is harmless. The q8_0 KV cache was reverted because it costs quality on long contexts and bought nothing.

The general lesson: tuning advice from a CUDA machine does not transfer to ROCm. Measure it.

## Non-text workloads

Through Lemonade, on the GPU unless stated. See [Lemonade](07-lemonade.md).

| Capability | Model | Result |
|---|---|---|
| Image generation | SDXL-Turbo | 512x512 in 8.6 s |
| Music | ACE-Step-Music | 30 s of audio in 21.5 s |
| Sound effects | ThinkSound-SFX | 9 s of audio in 9.8 s |
| Text to speech | MOSS-TTS-Local | 4.7 s of audio in 9.9 s |
| Image to 3D | TRELLIS-3D | 210 s, 79,811 vertices, 143,958 triangles, textured |
| NPU transcription | whisper-v3-turbo-FLM | works, no timestamps |

## Reproducing

```bash
scripts/bench-model.py gpt-oss:120b 3            # Ollama
scripts/bench-flm.py gpt-oss:20b 3               # FastFlowLM, needs flm serve on 11436
scripts/bench-lemonade.py <model> 3              # Lemonade, port 13305
scripts/bench-openai.py <base-url> <model> 3     # any OpenAI-compatible server, streaming; used for Halogen
scripts/bench-npu-vs-gpu.sh LABEL <any of the above>   # with power sampling
```
