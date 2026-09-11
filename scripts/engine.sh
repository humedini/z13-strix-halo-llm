#!/bin/bash
# Swap the Z13 between its two inference engines. They cannot share the memory.
#   engine.sh halogen   unload whatever Ollama holds, bring Halogen up, wait for healthy
#   engine.sh ollama    bring Halogen down; Ollama loads models on demand as usual
#   engine.sh status    what is resident right now
set -uo pipefail
H=~/z13-setup/halogen
status() {
  printf "  ollama:  "; curl -s -m 3 http://127.0.0.1:11434/api/ps | python3 -c "import json,sys; m=json.load(sys.stdin)['models']; print(', '.join(f\"{x['name']} ({x['size']/2**30:.0f} GiB)\" for x in m) or 'nothing loaded')" 2>/dev/null || echo "not answering"
  printf "  halogen: "; s=$(docker inspect --format '{{.State.Health.Status}}' halogen-engine-1 2>/dev/null); echo "${s:-down}"
  printf "  memory:  "; free -g | awk '/Mem/{print $7" GiB available"}'
}
case "${1:-status}" in
  halogen)
    for m in $(curl -s -m 3 http://127.0.0.1:11434/api/ps | python3 -c "import json,sys; print(' '.join(x['name'] for x in json.load(sys.stdin)['models']))" 2>/dev/null); do
      curl -s -o /dev/null http://127.0.0.1:11434/api/generate -d "{\"model\":\"$m\",\"keep_alive\":0}"; echo "  unloaded $m from Ollama"
    done
    (cd $H && docker compose up -d >/dev/null 2>&1) && echo "  halogen starting (first start after a reboot reads 121 GiB from disk, allow a few minutes)"
    for i in $(seq 1 120); do [ "$(docker inspect --format '{{.State.Health.Status}}' halogen-engine-1 2>/dev/null)" = healthy ] && break; sleep 5; done
    status;;
  ollama)
    (cd $H && docker compose down >/dev/null 2>&1) && echo "  halogen down"; sleep 2; status;;
  status) status;;
  *) sed -n 2,6p "$0";;
esac
