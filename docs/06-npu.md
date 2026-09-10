# 06. The NPU

## Status

The XDNA2 NPU in Strix Halo is usable for LLM inference on Linux as of March 2026, through [FastFlowLM](https://github.com/ROCm/FastFlowLM), which began as an independent project and has since moved under AMD's ROCm organisation. It runs standalone or as a backend inside Lemonade. Strix Halo is explicitly on its supported list.

**It is not fast**, and it is not more efficient per token than the GPU. What it offers is a low power ceiling and, more usefully, the ability to run a model while leaving the entire GPU and all 96 GiB of VRAM free for something else. Read the measurements before deciding it is worth setting up.

## Requirements

| Requirement | This machine |
|---|---|
| XDNA2 NPU | `RyzenAI-npu5`, `/dev/accel/accel0`, 8 columns |
| **Kernel 7.0 or newer** with `amdxdna` | 7.0.0-31. Ubuntu 26.04 ships exactly the floor |
| NPU firmware 1.1.0.0 or newer | 1.1.2.65, in the archive's `linux-firmware` |
| User in `render` group | yes; see [ROCm](03-rocm.md) |
| AMD XRT | `libxrt2` and `libxrt-npu2` are in the Ubuntu archive. Nothing from AMD's repos needed |
| **memlock raised** | see below; this blocks everything until fixed |

Install: FastFlowLM publishes an `ubuntu26.04` `.deb` on its releases page, and every dependency resolves from the archive. Script `15-npu-fastflowlm.sh`. Then run `flm validate`, which checks all of the above and is the only thing that reports the memlock problem clearly.

## The memlock blocker

```
[ERROR] Memlock limit is too low (8MB). Please raise the limit or set to infinity.
```

8 MB is the kernel default. The NPU pins model buffers far beyond it. **Two things must be raised, and raising only one is a common half fix:**

1. PAM limits, in `/etc/security/limits.d/`, which cover login shells
2. systemd's `DefaultLimitMEMLOCK=infinity`, via drop-ins for both `system.conf` and `user.conf`, which cover user services and anything launched from the graphical session. Those do not inherit PAM limits.

Script `16-npu-memlock.sh` does both. Then **log out and back in**. PAM applies limits at session creation, so the current session keeps the old value no matter what the config says. This is the usual reason "I set it and it did not work".

The Lemonade service picks up the systemd default automatically; `systemctl show lemond -p LimitMEMLOCK` should say `infinity`.

## Using it

```bash
flm list                        # models available for the NPU
flm pull gpt-oss:20b
flm serve gpt-oss:20b --port 11436     # OpenAI compatible, loopback
```

`flm run <model>` is an interactive REPL and does not accept a prompt argument. For scripting, use `serve` and the API. FastFlowLM reports `prefill_speed_tps` and `decoding_speed_tps` in the response `usage` object, which is convenient for measurement.

Supported families: Llama, Qwen (including a 35B-A3B MoE), Gemma, MedGemma, TranslateGemma, DeepSeek, gpt-oss, Phi, LiquidAI, Nanbeige, plus Whisper for audio, EmbeddingGemma for embeddings and SmolVLA for vision. Roughly the 1B to 35B class.

## Measured against the GPU

Identical weights, `gpt-oss:20b`, same prompts, APU package power sampled once a second. Full table in [benchmarks](05-benchmarks.md).

| | GPU | NPU |
|---|---|---|
| Generation | 46.79 tok/s | 18.96 tok/s |
| Prefill | 1547.6 tok/s | 301.4 tok/s |
| Time to first token | ~1.13 s | 6.01 s |
| Power, mean | 63.2 W | 27.1 W |
| Tokens per joule | 0.740 | 0.700 |

Two claims about Ryzen AI NPUs that circulate widely:

**"It reaches first token sooner."** Published figures say roughly 2.3x faster. Measured here it is **5.3x slower**, because its prefill is weak. That is the worst possible shape for interactive chat, where time to first token is what the wait feels like.

**"It is more efficient."** It draws less absolute power, 27 W against 63 W. But it is proportionally slower, so tokens per joule come out roughly equal with the GPU marginally ahead. Running a job on the NPU costs slightly **more** battery than running it on the GPU, not less.

The decode ratio, 2.47x in the GPU's favour, matched the published ~2.4x.

## What it is actually good for

**A 27 W ceiling instead of 85 W peaks.** The fans on this machine stay off below about 48°C, so NPU inference is near silent. No throttling on a handheld tablet.

**Leaving the GPU alone.** A small model answering on the NPU while a large one stays resident on the GPU is a real capability. Measured concurrently, the NPU lost only 1.5 percent of its generation speed with the GPU fully busy alongside it, and aggregate throughput rose 30 percent.

**Background and always-on work.** Embeddings, Whisper transcription without timestamps, a small assistant that must always be available. Anything where a 6 second time to first token does not matter.

**Not interactive chat.** Route that to the GPU.

## Hybrid: HRX

Lemonade 11.9 ships an experimental `llamacpp-hrx` backend on **HRX**, AMD's runtime from the ROCm Loom compiler and IR stack. It is an alternative HIP implementation intended as a common substrate across AMD GPUs, NPUs and CPUs, and Lemonade uses it to send prompt processing to the NPU and generation to the GPU for a single model. It targets RDNA3 discrete cards and Strix Halo.

Measured with `Qwen3-30B-A3B-Instruct-2507-HRX`:

| | GPU only | HRX | NPU only |
|---|---|---|---|
| Generation | 50.83 | **82.15 tok/s** | 18.96 |
| Prefill | 822.7 | 258.9 tok/s | 301.4 |
| Power, mean | ~63 W | 65.4 W | 27.1 W |
| Max prompt | full | **~500 tokens** | full |

Generation is **62 percent faster than GPU only**, which would make it the fastest configuration on the machine. It is also unusable:

```
E graph_compute: unsupported HRX node 2989: GET_ROWS ...
E llama_decode: failed to decode, ret = -3
BackendWatchdog: llama-server backend marked unavailable: GPU Hang / compute error detected
```

Above roughly 500 prompt tokens it hits an operation the backend has not implemented, the decode fails, and the watchdog kills the backend process. Any system prompt, document or multi turn history triggers it. Raising `ctx_size` does nothing; it is not a configuration issue.

Prefill is also 3.2 times worse than GPU only, and power is essentially GPU only power, so this is not an efficiency path either. The iGPU does the decode work, as documented.

Left installed, not used. Worth rechecking after Lemonade updates: if `GET_ROWS` lands and prefill improves, this becomes the default.

Note the GPU only figure is `qwen3-coder:30b-a3b`, a different model of the same architecture and active count. Treat 62 percent as indicative rather than exact.

## Transcription on the NPU

`whisper-v3-turbo-FLM` transcribes correctly. Its backend returns only `{model, text}`: no segments, no words, no timestamps, regardless of `response_format` or `timestamp_granularities`. That makes it fine for plain transcription and useless for diarisation, which needs timestamps to align against. See [speech](08-speech.md).
