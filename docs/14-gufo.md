# 14. Gufo, speculative decoding, and why Halogen was retired

[Halogen](12-halogen.md) was the fastest way to run Qwen3.8-Flash-Next here, at the price of the BIOS on Auto and the whole machine. Two weeks later a second purpose-built engine matched it on generation and beat it on prefill without that price. This page covers that engine, the speculative decoding results on three model families, and what was removed as a result.

## Gufo

[gufo-org/gufo](https://github.com/gufo-org/gufo) is an MIT-licensed C++ OpenAI-compatible server written for `gfx1151`. It reads ordinary GGUF files, supports three speculative modes (`dflash2`, `mtp`, `dspark`), and also serves Qwen-Image, MiniMax video and Qwen3 ASR/TTS. At the time of testing it was six weeks old with no tagged releases, so treat it as moving.

It ships as a container, `ghcr.io/gufo-org/toolboxes/gufo-runtime` (8.3 GB). Running it under Docker:

- `--device /dev/kfd --device /dev/dri --group-add 990 --group-add 44`. Use the **numeric** `render` and `video` GIDs from `getent group render video`; the names do not exist inside the image.
- The entry point is `/bin/gufo-server`, with subcommands `serve`, `bench` and `diagnose`.
- Mount the model directory read-only.
- `--api-key` is supported, so it can be published on the tailnet the same way as everything else in [remote access](09-remote-access.md).

`scripts/gufo-up.sh` starts Flash-Next on loopback with an API key and refuses to start if the GPU is busy. `scripts/engine.sh gufo|ollama|status` swaps it with Ollama, since a 111 GB model and a large Ollama model cannot share the memory.

**It rejects IQ quants.** `IQ3_S`, `IQ4_XS` and friends fail with "unsupported format". Use `Q4_K_XL` or similar `K` quants. For Flash-Next that means about 111 GB instead of 94.

## Flash-Next, three engines

Same harness throughout ([benchmarks](05-benchmarks.md), `scripts/bench-openai.py`): about 2K prompt tokens, 400 generated, median of three, performance profile.

| Engine | Weights | Generation | Prefill | Time to first token | Notes |
|---|---|---|---|---|---|
| llama.cpp Vulkan b10964 | UD-IQ4_XS, 94 GB | 26.2 tok/s | 316 tok/s | | thinking switchable, coexists with other work |
| Gufo, plain | UD-Q4_K_XL, 111 GB | 25.1 tok/s | 1,110 tok/s | 2.1 s | |
| Gufo, MTP | UD-Q4_K_XL + shared MTP head | **33.5 tok/s** | **1,080 tok/s** | | |
| Halogen | own format, 115 GiB | 35.3 tok/s | 665 tok/s | 3.5 s | BIOS on Auto, thinking forced on |

Gufo with MTP is within noise of Halogen on generation, has 1.6 times its prefill and 3.4 times llama.cpp's, and needs nothing from the BIOS. It also has the two things Halogen lacked: a switch to turn thinking off, and an API key. It loads in about 40 seconds from NVMe and holds about 85 GiB of GPU memory, leaving around 20 GiB for everything else.

MTP does not work for this model under llama.cpp yet. Mainline lacks the Flash-Next (`qwen4exp`) MTP graph, and the unsloth fork's Vulkan build loads the head and then aborts on `GGML_ASSERT(ggml_can_repeat(b, a))`, with both the shared and the self-contained head.

With thinking on, Flash-Next spends a large share of every answer reasoning. Under llama.cpp it can be turned off per request with `"chat_template_kwargs": {"enable_thinking": false}`; under Gufo with `--think off` at startup. For short questions that matters more than any number in the table.

## Speculative decoding on a dense model

Qwen3.8 27B dense was the slowest model in the [README table](../README.md) at 10.7 tok/s, because every token reads all 27B parameters. Speculative decoding is the fix, and the engine decides how much of it you get.

| Engine and mode | Generation | Prefill |
|---|---|---|
| llama.cpp Vulkan, plain (UD-Q4_K_XL) | 11.5 tok/s | ~165 tok/s |
| llama.cpp Vulkan, MTP head, `--spec-draft-n-max 2` | 17.8 tok/s | ~165 tok/s |
| llama.cpp Vulkan, MTP head, `--spec-draft-n-max 3` | 15.1 tok/s | |
| Gufo, plain | 11.6 tok/s | 482 tok/s |
| Gufo, DFlash2 drafter (z-lab `Qwen3.8-27B-DFlash2`, Q8_0) | **24.6 tok/s** | 442 tok/s |

MTP under llama.cpp accepted 60 to 64 percent of drafted tokens; drafting three at a time instead of two made it slower, because the third is accepted too rarely to pay for itself. DFlash2 more than doubles generation. Gufo's own `bench` tool reported 22.7 tok/s for the same setup; the 70 tok/s in Gufo's README is a best case on favourable text. Time to first token was 4.8 s at 2K.

So the dense 27B goes from the slowest model on the machine to faster than `qwen3.5:122b` was under Ollama, and the "dense, avoid" advice in the README needs that qualification.

## DeepSeek V4 Flash

DeepSeek V4 Flash 0731 at unsloth UD-IQ2_XXS (85 GiB) under llama.cpp Vulkan: 14.8 tok/s plain, **19.5 tok/s** with the DSpark drafter (`--spec-type draft-dspark --spec-draft-n-max 3`, drafter fully offloaded with `-ngld 99`), prefill about 165 tok/s. Loaded with its drafter it leaves about 17 GiB free, so nothing else large runs alongside it. Gufo cannot load it (IQ quant).

DeepSeek V4.1 Flash cannot run on this machine at all: 152 GiB resident even at 2-bit, plus 189 GiB of tables read from SSD, and at the time of writing its runner was Metal only.

## What was removed

Halogen went: container, image, 121 GiB of weights and its tailnet port. Its compose file stays in the repository for reference, and [Halogen](12-halogen.md) stays as the record of what it measured. `scripts/engine.sh` now swaps Gufo and Ollama. Gufo was measured with the BIOS on Auto; it was not tried under the 96 GiB carve-out.

## Reproducing

```bash
scripts/gufo-up.sh                 # Flash-Next on 127.0.0.1:8099 with MTP; down | status | key
scripts/engine.sh status           # what is resident
scripts/serve-bench.sh LABEL -- -m model.gguf [llama-server args]   # llama.cpp Vulkan, starts, measures, stops
scripts/bench-openai.py http://127.0.0.1:8099/v1 <model> 3          # any of them; set OPENAI_API_KEY=$(scripts/gufo-up.sh key) for Gufo
```
