#!/usr/bin/env python3
"""
Benchmark an Ollama model honestly.

Two traps this avoids:
  1. Ollama caches prompts. Repeating an identical prompt returns a cached
     prefill and reports absurd numbers (~5900 tok/s vs a true ~275). Every run
     here uses a unique prompt.
  2. Generation speed varies by roughly 2.4 tok/s run to run on this machine, so
     a single sample cannot support a claim about a 10% difference. This takes
     several and reports the median and the spread.

Usage: bench-model.py <model> [runs] [num_predict]
"""
import json, statistics, sys, time, urllib.request, uuid

model = sys.argv[1]
runs = int(sys.argv[2]) if len(sys.argv) > 2 else 3
npred = int(sys.argv[3]) if len(sys.argv) > 3 else 400
URL = "http://127.0.0.1:11434/api/generate"

def one(i):
    # Unique filler each run defeats the prompt cache.
    nonce = uuid.uuid4().hex
    filler = (f"Reference block {nonce} item {i}. Memory bandwidth bound accelerators "
              "read weights per token, so active parameter count governs speed. ") * 40
    body = json.dumps({"model": model, "prompt": filler +
                       "\n\nExplain in detail, in several paragraphs, what governs "
                       "inference speed on a memory-bandwidth-bound accelerator, why "
                       "mixture-of-experts models behave differently from dense ones, and "
                       "how quantisation interacts with both.",
                       "stream": False,
                       "options": {"num_predict": npred, "temperature": 0.7, "seed": i}}).encode()
    r = urllib.request.urlopen(urllib.request.Request(
        URL, body, {"Content-Type": "application/json"}), timeout=3600)
    d = json.load(r)
    return (d.get("prompt_eval_count", 0), d.get("prompt_eval_duration", 1),
            d.get("eval_count", 0), d.get("eval_duration", 1), d.get("load_duration", 0))

print(f"  model: {model}   runs: {runs}")
pf, gn = [], []
for i in range(runs):
    pc, pd, ec, ed, ld = one(i)
    p, g = pc / (pd / 1e9), ec / (ed / 1e9)
    pf.append(p); gn.append(g)
    print(f"    run {i+1}: prompt {pc:>5} tok @ {p:>8.1f} tok/s   gen {ec:>4} tok @ {g:>6.2f} tok/s"
          + (f"   (load {ld/1e9:.1f}s)" if ld > 1e9 else ""))

def rep(name, xs):
    med = statistics.median(xs)
    print(f"  {name:<10} median {med:>8.2f}   min {min(xs):>8.2f}   max {max(xs):>8.2f}   spread {max(xs)-min(xs):>6.2f}")

print()
rep("PREFILL", pf)
rep("GEN", gn)
