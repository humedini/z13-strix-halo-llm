#!/usr/bin/env python3
"""Prefill and generation against an OpenAI-compatible endpoint at several context depths.
Unique prompt per run (no cache hits), streaming, 400-token generations, median of N.
Reports client-side numbers; for Halogen cross-check `docker compose logs api | grep serve_api`.

Usage: bench-depth.py <base_url> <model> [runs] [depths, comma separated tokens]
   e.g. bench-depth.py http://127.0.0.1:8731/v1 halogen-qwen3.8-flash-next 3 2000,8000,16000,32000
"""
import json, statistics, sys, time, urllib.request, uuid
base=sys.argv[1].rstrip("/"); model=sys.argv[2]
runs=int(sys.argv[3]) if len(sys.argv)>3 else 3
depths=[int(x) for x in (sys.argv[4] if len(sys.argv)>4 else "2000,8000,16000,32000").split(",")]
SENT=("The accelerator reads every active weight once per generated token, so bandwidth sets the ceiling on decode "
      "while prefill is bounded by compute; mixture of experts lowers the bytes touched per token without shrinking the model. ")
def one(depth, i):
    nonce=uuid.uuid4().hex
    reps=max(1, depth//54)   # SENT measures about 54 tokens on the Qwen tokenizer
    filler="".join(f"[{nonce[:8]}-{k}] {SENT}" for k in range(reps))
    body=json.dumps({"model":model,"stream":True,"stream_options":{"include_usage":True},
        "messages":[{"role":"user","content":filler+"\n\nSummarise the argument above in several paragraphs, then explain how quantisation changes it."}],
        "max_tokens":400,"temperature":0}).encode()
    req=urllib.request.Request(f"{base}/chat/completions",body,{"Content-Type":"application/json"})
    t0=time.time(); t_first=None; n=0; usage=None
    with urllib.request.urlopen(req,timeout=3600) as r:
        for line in r:
            line=line.decode().strip()
            if not line.startswith("data:"): continue
            p=line[5:].strip()
            if p=="[DONE]": break
            d=json.loads(p)
            if d.get("usage"): usage=d["usage"]
            ch=d.get("choices") or []; delta=(ch[0].get("delta") or {}) if ch else {}
            if delta.get("content") or delta.get("reasoning_content"):
                if t_first is None: t_first=time.time()
                n+=1
    t_end=time.time(); ptok=(usage or {}).get("prompt_tokens",0); ctok=(usage or {}).get("completion_tokens",n)
    ttft=(t_first or t_end)-t0; gen_s=t_end-(t_first or t_end)
    return ptok, ttft, ptok/ttft if ttft>0 else 0, ctok, ctok/gen_s if gen_s>0 else 0
print(f"  endpoint {base}  model {model}  runs {runs}")
print(f"  {'depth':>7} {'prompt':>7} {'ttft':>7} {'prefill':>9} {'gen':>7}   (medians of {runs})")
for depth in depths:
    rs=[one(depth,i) for i in range(runs)]
    ptok=int(statistics.median(r[0] for r in rs)); ttft=statistics.median(r[1] for r in rs)
    pf=statistics.median(r[2] for r in rs); gen=statistics.median(r[4] for r in rs)
    spread=max(r[4] for r in rs)-min(r[4] for r in rs)
    print(f"  {depth:>7} {ptok:>7} {ttft:>6.1f}s {pf:>7.0f}/s {gen:>6.1f}/s   gen spread {spread:.1f}", flush=True)
