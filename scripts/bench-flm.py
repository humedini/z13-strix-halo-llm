#!/usr/bin/env python3
"""Benchmark FastFlowLM (NPU) with the same methodology as bench-model.py:
unique prompt per run, 400-token generations, median of three.
Uses FLM's own reported prefill/decode speeds from the usage object."""
import json, statistics, sys, urllib.request, uuid
model = sys.argv[1]; runs = int(sys.argv[2]) if len(sys.argv) > 2 else 3
port = sys.argv[3] if len(sys.argv) > 3 else "11436"
URL = f"http://127.0.0.1:{port}/v1/chat/completions"
pf, gn, ttft = [], [], []
print(f"  model: {model} (NPU)   runs: {runs}")
for i in range(runs):
    nonce = uuid.uuid4().hex
    filler = (f"Reference block {nonce} item {i}. Memory bandwidth bound accelerators "
              "read weights per token, so active parameter count governs speed. ") * 40
    body = json.dumps({"model": model, "messages": [{"role": "user", "content": filler +
        "\n\nExplain in detail, in several paragraphs, what governs inference speed on a "
        "memory-bandwidth-bound accelerator, why mixture-of-experts models behave "
        "differently from dense ones, and how quantisation interacts with both."}],
        "max_tokens": 400}).encode()
    d = json.load(urllib.request.urlopen(urllib.request.Request(
        URL, body, {"Content-Type": "application/json"}), timeout=1800))
    u = d.get("usage", {})
    p = u.get("prefill_speed_tps", 0); g = u.get("decoding_speed_tps", 0)
    t = u.get("prefill_duration_ttft", 0)
    pf.append(p); gn.append(g); ttft.append(t)
    print(f"    run {i+1}: prompt {u.get('prompt_tokens',0):>5} tok @ {p:>8.1f} tok/s   "
          f"gen {u.get('completion_tokens',0):>4} tok @ {g:>6.2f} tok/s   ttft {t:.2f}s")
def rep(n, xs, unit=""):
    print(f"  {n:<10} median {statistics.median(xs):>8.2f}{unit}   min {min(xs):>8.2f}   max {max(xs):>8.2f}   spread {max(xs)-min(xs):>6.2f}")
print(); rep("PREFILL", pf); rep("GEN", gn); rep("TTFT", ttft, "s")
