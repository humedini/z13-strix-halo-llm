# 12. Halogen: a second inference engine, and the BIOS trade it forces

[peonist-ai/halogen-flash-server](https://github.com/peonist-ai/halogen-flash-server) is a purpose-built server for Strix Halo that runs its own model format, `halogen-qwen3.8-flash-next`, a 4-bit Qwen3.8-Flash-Next at 115 GiB of weights. Upstream claims a large speed advantage over llama.cpp-based stacks on this hardware. This page is what it took to run it, what it measured, and what it cost elsewhere.

## The BIOS requirement

Halogen allocates its weights from **host RAM** through unified memory and pins them, which is why the container needs `memlock` unlimited. A firmware VRAM carve-out is memory it cannot see. Its reference configurations are a 512 MB UMA frame buffer or "UMA Auto".

On the 96 GiB carve-out described in [hardware](01-hardware.md), the host has 30 GiB and Halogen cannot load at all. So running it means BIOS: Advanced, UMA Frame Buffer Size, **Auto**. On this machine that gives:

| | 96 GiB carve-out | Auto |
|---|---|---|
| VRAM | 96 GiB | 0.5 GiB |
| System RAM | 30 GiB | 122 GiB |
| GTT (what the GPU can borrow) | 15 GiB | 61.3 GiB |

Everything else on the machine now runs from GTT. What that costs is measured in [benchmarks](05-benchmarks.md#carve-out-versus-gtt): about 7 to 9 percent on generation, nothing on prefill. What it breaks: Ollama sees 61 GiB, so `laguna-S-2.1` (92 GiB) and `gpt-oss:120b` (65 GiB) no longer load until the GTT cap is raised. `scripts/24-gttsize.sh` sets `amdgpu.gttsize=108544` (106 GiB) and the matching `ttm.pages_limit` on the kernel command line for that; it needs a reboot, and both are required, see [hardware](01-hardware.md).

Getting into the BIOS on this machine: hold F2 at power on, or `systemctl reboot --firmware-setup`. The latter can be refused with "operation inhibited" while a session holds an inhibitor lock; close what is holding it or use F2.

## Running it under Docker

Upstream targets podman. The compose file in [`halogen/`](../halogen/docker-compose.yml) is the Docker adaptation. The differences that mattered:

- `group_add: ["990", "44"]`, the `render` and `video` GIDs, or the container cannot open `/dev/kfd` and `/dev/dri`. Look yours up with `getent group render video`.
- `ports: ["127.0.0.1:8731:8731"]` on the API container, loopback only, published to the tailnet with `scripts/23-halogen-tailnet.sh`. Halogen accepts any `Host` header, so it needs no shim, unlike Ollama.
- `ulimits: {memlock: -1}` and `ipc: host` as upstream specifies; `seccomp: unconfined` was needed for the ROCm runtime.
- The health check `start_period` is 20 minutes. Upstream reports first starts between 2 and 44 minutes while the weights are mapped and pinned. On this machine, with the weights already in page cache, the engine was healthy in 30 seconds.

```bash
cd halogen
docker compose up -d
docker compose logs -f engine
curl -s http://127.0.0.1:8731/health
curl -s http://127.0.0.1:8731/v1/models
docker compose down          # releases roughly 115 GiB of pinned host RAM
```

Do not run large Ollama models while Halogen is up. Both want the same memory and there is one pool.

The weights come from Hugging Face with `hf download peonist-ai/halogen-qwen3.8-flash-next`, 121 GiB on disk including a vision tower and two overlays. The engine log tells you which it loaded.

## Measured

Same harness as everything else here: unique prompt per run, about 2,200 prompt tokens, 400 generated tokens, median of three, TDP 70/86/86 W, APU package power sampled once a second. Two independent measurements agree: the client-side streaming timer in `scripts/bench-openai.py`, and Halogen's own `serve_api` log line, which reports prefill and decode separately.

| | Halogen `qwen3.8-flash-next` | Ollama `qwen3.5:122b` (carve-out) | Ollama `gpt-oss:120b` (carve-out) |
|---|---|---|---|
| Weights | 115 GiB, 4-bit | 81 GB | 65 GB |
| Prefill | **665 tok/s** | 194 tok/s | 289 tok/s |
| Generation | **35.3 tok/s** | 22.0 tok/s | 31.6 tok/s |
| Time to first token, 2.2K prompt | 3.5 s | 11.5 s | 7.6 s |
| APU power, mean | 87 W | 75 W | 77 W |

Decode ran between 31.8 and 36.9 tok/s across seven server-side samples. Halogen uses multi-token prediction with a drafter, and the log shows it committing about two tokens per round; that is where the generation advantage comes from.

Read this carefully. The models differ. Qwen3.8-Flash-Next is a newer and larger model than either Ollama comparison, so this is a comparison of two stacks as deployed, not a controlled test of the engine. Taken that way: **1.6 times the generation speed and 3.4 times the prefill of the largest model Ollama runs here**, at 12 W more. It is not the several-fold generation gain upstream describes, and on generation it is only modestly ahead of `gpt-oss:120b`, a much smaller model.

What Halogen unambiguously wins is prefill. Long documents, big code files and RAG contexts hit the model at 665 tok/s, three times anything Ollama managed, and that is what time to first token is made of.

## Independent confirmation

The day after these measurements, Donato Capitella published [a benchmark of Qwen3.8-Flash-Next on Strix Halo](https://www.youtube.com/watch?v=Nm_zN6RQ_eE) covering llama.cpp on ROCm, Nathan Wilson's Vulkan fork, [EngramHalo.cpp](https://github.com/Aristo94/EngramHalo.cpp) and Halogen, with speed measured at context depths up to 64K and quality checked with his 19-task [Terminal Bench Mini](https://kyuz0.github.io/terminal-bench-mini/). The video is sponsored by AMD and says so. His Halogen figures are 752 tok/s prefill and 41 tok/s decode at 32K context, still 700 and 37 at 64K, roughly double the Vulkan fork on both axes. Halogen completed all 19 tasks, 18 at the first attempt; EngramHalo completed 16. His machine is an AMD AI Halo mini desktop, the same silicon in a chassis with a larger power budget and a proper cooler; the depth comparison is in the table below.

His explanation of the model's n-gram embedding table is the clearest available: 51 billion learned parameters that are looked up rather than multiplied, placed after the first layer so the lookup overlaps GPU work, gated per token, and small enough per lookup that the table can live on SSD. That is why the Halogen weights are 115 GiB and why the engine wants host RAM rather than a VRAM carve-out.

Halogen's author has said he intends to open-source the server and the kernel optimisation method. Until then it is a binary you cannot inspect, which is fine on a home machine and worth knowing.

## Depth sweep, and what the power budget is worth

Prompted by the video, the same benchmark at four context depths, three runs each, 400 generated tokens, client-side timing cross-checked against the server log. Depths are measured prompt tokens.

| Prompt tokens | Time to first token | Prefill | Generation | TDP |
|---|---|---|---|---|
| 2.9K | 4.0 s | 737 tok/s | 34.9 tok/s | 70 W |
| 12K | 11.5 s | 1041 tok/s | 33.1 tok/s | 70 W |
| 24K | 22.0 s | 1086 tok/s | 33.3 tok/s | 70 W |
| 48K | 42.9 s | 1116 tok/s | 32.6 tok/s | 70 W |
| 3K | 4.0 s | 738 tok/s | 34.6 tok/s | 90 W |
| 47K | 39.0 s | 1207 tok/s | 33.4 tok/s | 90 W |

Three things fall out of it.

**Prefill gets faster with depth.** Larger batches use the GPU better, and at 48K the tablet at 70 W is ahead of the 752 tok/s the video measured at 32K. The engine's own published figure is 1424 tok/s at 32K, measured with the IOMMU off, which its author says is worth 13 to 16 percent of prefill. This machine has the IOMMU on, in passthrough mode. Turning it off is a kernel parameter and a reboot, and on a portable machine it is also the protection against DMA attacks over USB4, so it is a choice rather than a default.

**Generation does not care about power.** 90 W bought 8 percent of prefill and nothing on generation, which is memory bound. The 20 W sat unused, and the fans ran at 8600 rpm for it. On this machine the 70 W profile is the ceiling that matters, and the quiet profile costs less than it sounds.

**Generation barely moves with depth.** Sixteen times the context cost 7 percent. That is the engine's design working: a single KV pool with the prompt cache kept in place.

The remaining gap is generation: 33 to 37 tok/s here against the video's 41 and the engine's published 41.7 mean with speculative decoding, whose serial figure is 34.1. Speculative decoding is on here too, committing between 1.8 and 2.7 tokens per round depending on the text, and a code prompt was no faster than prose. The likeliest explanations are the IOMMU, which sits in the path of the paged n-gram table that every token reads, and the prompt set the mean was taken over. Untested.

The engine author publishes a kernel command line for reproducing the figures: `amdgpu.vm_update_mode=0 amdgpu.noretry=0 amdgpu.gttsize=126976 ttm.pages_limit=32505856 amdgpu.sg_display=0 amd_iommu=off`. This machine runs `gttsize` and `ttm.pages_limit` from script 24 and none of the rest.

## Two measurement traps

**Thinking models stream `reasoning_content` first.** Halogen's model reasons before it answers, and the OpenAI-compatible stream carries that in `delta.reasoning_content`, with `delta.content` empty until the answer starts. A client that starts its generation timer on the first `content` chunk never starts it, reports time to first token equal to the whole request, and divides 400 tokens by zero seconds. The first version of `bench-openai.py` did exactly that and reported `0.00 tok/s`. Count either field.

**A prompt that differs only at the end hits the prefix cache.** The obvious way to separate prefill from generation without streaming is two requests, one with `max_tokens=1` and one with the full budget, and subtract. If the second prompt shares its prefix with the first, Halogen's cache serves it in 0.06 seconds (`2170 cached` in the log), the subtraction removes a prefill that was never paid, and generation reads 50 tok/s instead of 35. Ollama has the same cache and the same trap, described in [benchmarks](05-benchmarks.md). Change the prompt at the start, or use the server's own timings.

## Where it fits

Halogen is the right tool when the workload is long prompts on the biggest model, and the whole machine can be given to it. It is the wrong tool for the mixed use this machine mostly sees, where Ollama's model switching, Open WebUI integration and 15 second model loads matter more than a third more tokens per second. Both can be installed. Only one can be loaded.

`scripts/engine.sh halogen` and `scripts/engine.sh ollama` swap between the two, unloading whatever the other holds, since they cannot share the memory. `scripts/bench-depth.py` is the depth sweep.

The BIOS trade is the real decision. Auto costs every other model on the machine 7 to 9 percent of its generation speed and, without the `gttsize` change, the two largest Ollama models altogether. It makes the 122 GiB of host RAM available to everything else, which the 30 GiB split never did. That is a better default for a machine that is also used as a computer.
