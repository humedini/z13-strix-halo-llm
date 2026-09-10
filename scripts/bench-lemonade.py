#!/usr/bin/env python3
"""Benchmark a Lemonade model using its llama.cpp `timings` block.
Same methodology as the other harnesses: unique prompt per run to defeat the
prompt cache, 400-token generations, median of three."""
import json, statistics, sys, urllib.request, uuid
model = sys.argv[1]; runs = int(sys.argv[2]) if len(sys.argv) > 2 else 3
URL = "http://127.0.0.1:13305/api/v1/chat/completions"
pf, gn = [], []
print(f"  model: {model}   runs: {runs}")
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
    t = d.get("timings") or {}
    p = t.get("prompt_per_second", 0); g = t.get("predicted_per_second", 0)
    pf.append(p); gn.append(g)
    print(f"    run {i+1}: prompt {t.get('prompt_n',0):>5} tok @ {p:>8.1f} tok/s   "
          f"gen {t.get('predicted_n',0):>4} tok @ {g:>6.2f} tok/s")
def rep(n, xs):
    print(f"  {n:<10} median {statistics.median(xs):>8.2f}   min {min(xs):>8.2f}   max {max(xs):>8.2f}   spread {max(xs)-min(xs):>6.2f}")
print(); rep("PREFILL", pf); rep("GEN", gn)
