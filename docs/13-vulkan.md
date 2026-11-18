# 13. The engine is the biggest lever: llama.cpp Vulkan against Ollama

[Inference](04-inference.md) quoted published figures showing Vulkan ahead of ROCm on generation and said an A/B was not chased. This page is that A/B, run on this machine with the **same GGUF file** loaded by both engines, so the only variable is the engine.

## Setup

- llama.cpp official Vulkan build `b10964` from the `ggml-org` releases, unpacked into its own directory. The `llama-*` binaries the base installer put in `/usr/local/bin` are CPU only; check with `llama-server --list-devices` before trusting a number from them.
- Ollama as configured in [inference](04-inference.md), ROCm backend.
- Both pointed at the blob in Ollama's own store (`ollama show --modelfile <model>` prints its path on the `FROM` line). Ollama's model directory is owned by the `ollama` user; a read-only ACL for your user (`setfacl -R -m u:$USER:rX` on the models directory) lets llama.cpp read it without a second copy.
- BIOS memory on Auto (weights in GTT), quiet power profile, the repo harness `scripts/bench-openai.py`: about 2K prompt tokens, 400 generated, median of three, unique prompt per run.
- `scripts/vulkan-bench.sh` does the llama-bench half of this from an Ollama model name.

## Measured, 2026-09-17

| Model | Engine | Generation | Prefill |
|---|---|---|---|
| `qwen3-coder:30b-a3b` Q4_K_M (MoE, 3B active) | Ollama ROCm | 42.1 tok/s | 988 tok/s |
| same file | llama-server Vulkan | **67.8 tok/s** | 830 tok/s |
| same file | llama-bench Vulkan, zero depth | 78.9 tok/s | 966 to 983 tok/s |
| `qwen3.8:27b` (dense) | Ollama ROCm | 10.6 tok/s | 217 tok/s |
| same file | llama-server Vulkan | 12.0 tok/s | 177 tok/s |

**On a MoE model Vulkan generates 61 percent faster from identical weights.** On a dense model the gap is 13 percent, and ROCm still wins prefill on both. That matches the published direction in [inference](04-inference.md), but the MoE gap here is larger than the 33 percent published, which is the reason to measure your own machine.

llama-bench reads higher than llama-server because it measures at zero context depth with no HTTP or sampling overhead. Use the server figure when comparing with anything else in this repository.

## Settings that mattered and did not

- **`-ub 2048`** (micro-batch) took prefill from 755 to between 966 and 983 tok/s. The default of 512 leaves prefill on the table. It costs nothing on generation.
- **`q8_0` KV cache** made no measurable difference at 2K depth, consistent with the CUDA tuning finding in [benchmarks](05-benchmarks.md#tuning-that-changed-nothing).
- This build wants `-fa on` and `--load-mode none`. The older spellings `-fa 1`, `-mmp` and `--no-mmap` are rejected, which matters if you copy commands from older posts.

## Ollama files llama.cpp will not load

Not every Ollama blob is a portable GGUF:

- **`gpt-oss` blobs** are tagged with architecture `gptoss`. llama.cpp expects `gpt-oss` and refuses them.
- **`qwen3.5:122b`** has three entries in `rope.dimension_sections`; llama.cpp expects four.
- `qwen3moe` and `qwen35` blobs (qwen3-coder, the 27B) load fine.

For the two that fail, download the upstream GGUF from Hugging Face instead.

## Ollama under Auto, for comparison

The headline table in the README was measured under the 96 GiB carve-out. Re-measured under Auto with the same harness on the same day: `gpt-oss:120b` 27.3 to 27.8 tok/s (was 31.6), `qwen3.5:122b` 19.1 tok/s (was 22.0). That is a 12 to 13 percent drop, a little more than the 7 to 9 percent in [benchmarks](05-benchmarks.md#carve-out-versus-gtt), and the quiet profile probably accounts for the rest.

## What this changes

For MoE models, which are most of what is worth running here, the engine is now a bigger lever than any setting inside Ollama. Ollama keeps its place for convenience: model switching, Open WebUI, 15 second loads. For a model you run all day, serve it with llama-server Vulkan, or with [Gufo](14-gufo.md) if it is in a format Gufo takes.
