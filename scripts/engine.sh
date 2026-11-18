#!/bin/bash
# Swap the Z13 between its inference engines. A 111 GB model and a large Ollama model cannot share the memory.
#   engine.sh gufo      unload whatever Ollama holds, bring Flash-Next up under Gufo (scripts/gufo-up.sh)
#   engine.sh ollama    stop Gufo; Ollama loads models on demand as usual
#   engine.sh status    what is resident right now
# Halogen was retired 2026-09-24 in favour of Gufo, see docs/14-gufo.md.
set -uo pipefail
UP="$(dirname "$(readlink -f "$0")")/gufo-up.sh"
status() {
  printf "  ollama:  "; curl -s -m 3 http://127.0.0.1:11434/api/ps | python3 -c "import json,sys; m=json.load(sys.stdin)['models']; print(', '.join(f\"{x['name']} ({x['size']/2**30:.0f} GiB)\" for x in m) or 'nothing loaded')" 2>/dev/null || echo "not answering"
  printf "  gufo:    "; docker ps --filter name=^gufo-flash-next$ --format '{{.Status}}' | grep . || echo down
  printf "  memory:  "; free -g | awk '/Mem/{print $7" GiB available"}'
}
case "${1:-status}" in
  gufo)
    for m in $(curl -s -m 3 http://127.0.0.1:11434/api/ps | python3 -c "import json,sys; print(' '.join(x['name'] for x in json.load(sys.stdin)['models']))" 2>/dev/null); do
      curl -s -o /dev/null http://127.0.0.1:11434/api/generate -d "{\"model\":\"$m\",\"keep_alive\":0}"; echo "  unloaded $m from Ollama"
    done
    "$UP"; status;;
  ollama) "$UP" down; sleep 2; status;;
  status) status;;
  *) sed -n 2,6p "$0";;
esac
