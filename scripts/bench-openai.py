#!/usr/bin/env python3
"""Benchmark any OpenAI-compatible chat endpoint by wall clock, streaming.

Reports time to first token, prefill rate (prompt tokens / TTFT), and
generation rate (completion tokens / streaming time after first token).
Same discipline as bench-model.py: unique prompt per run to defeat any prompt
cache, 400-token generations, median of three with spread.

Usage: bench-openai.py <base_url> <model> [runs]
   e.g. bench-openai.py http://127.0.0.1:8731/v1 qwen3.8-flash-next 3
"""
import json, statistics, sys, time, urllib.request, uuid

base = sys.argv[1].rstrip("/"); model = sys.argv[2]
runs = int(sys.argv[3]) if len(sys.argv) > 3 else 3
ttft_l, pf_l, gen_l = [], [], []
print(f"  endpoint: {base}   model: {model}   runs: {runs}")
for i in range(runs):
    nonce = uuid.uuid4().hex
    filler = (f"Reference block {nonce} item {i}. Memory bandwidth bound accelerators "
              "read weights per token, so active parameter count governs speed. ") * 40
    body = json.dumps({"model": model, "stream": True,
        "stream_options": {"include_usage": True},
        "messages": [{"role": "user", "content": filler +
            "\n\nExplain in detail, in several paragraphs, what governs inference speed on a "
            "memory-bandwidth-bound accelerator, why mixture-of-experts models behave "
            "differently from dense ones, and how quantisation interacts with both."}],
        "max_tokens": 400, "temperature": 0}).encode()
    req = urllib.request.Request(f"{base}/chat/completions", body,
                                 {"Content-Type": "application/json"})
    t0 = time.time(); t_first = None; n_chunks = 0; usage = None
    with urllib.request.urlopen(req, timeout=3600) as r:
        for line in r:
            line = line.decode().strip()
            if not line.startswith("data:"): continue
            payload = line[5:].strip()
            if payload == "[DONE]": break
            d = json.loads(payload)
            if d.get("usage"): usage = d["usage"]
            ch = d.get("choices") or []
            delta = (ch[0].get("delta") or {}) if ch else {}
            if delta.get("content") or delta.get("reasoning_content"):   # thinking models stream reasoning_content first
                if t_first is None: t_first = time.time()
                n_chunks += 1
    t_end = time.time()
    ptok = (usage or {}).get("prompt_tokens", 0); ctok = (usage or {}).get("completion_tokens", n_chunks)
    ttft = (t_first or t_end) - t0
    gen_s = t_end - (t_first or t_end)
    pf = ptok / ttft if ttft > 0 and ptok else 0
    gen = ctok / gen_s if gen_s > 0 else 0
    ttft_l.append(ttft); pf_l.append(pf); gen_l.append(gen)
    print(f"    run {i+1}: prompt {ptok:>5} tok  ttft {ttft:5.2f}s ({pf:6.1f} tok/s)   "
          f"gen {ctok:>4} tok @ {gen:6.2f} tok/s")
def rep(n, xs, u=""):
    print(f"  {n:<10} median {statistics.median(xs):>8.2f}{u}   min {min(xs):>8.2f}   max {max(xs):>8.2f}   spread {max(xs)-min(xs):>6.2f}")
print(); rep("TTFT", ttft_l, "s"); rep("PREFILL", pf_l); rep("GEN", gen_l)
