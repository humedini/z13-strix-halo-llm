#!/bin/bash
# llama-bench (official llama.cpp Vulkan build) on the same blob Ollama uses. See docs/13-vulkan.md.
# usage: vulkan-bench.sh <ollama-model> [server]      LLAMA_DIR = unpacked bNNNN Vulkan release
# Your user needs read access to Ollama's model store, e.g. setfacl -R -m u:$USER:rX /usr/share/ollama/.ollama/models
set -u
D=${LLAMA_DIR:-$HOME/llama-vulkan/b10964}; export LD_LIBRARY_PATH=$D
M=${1:?ollama model name}; MODE=${2:-bench}
BLOB=$(ollama show --modelfile "$M" | awk '/^FROM \//{print $2; exit}')
[ -r "$BLOB" ] || { echo "cannot read $BLOB - grant access first"; exit 2; }
ollama ps | awk 'NR>1{print $1}' | xargs -r -n1 ollama stop   # free the GPU
echo "model $M  blob $(du -h "$BLOB" | cut -f1)  $(free -g | awk 'NR==2{print "avail "$7" GiB"}')"
if [ "$MODE" = bench ]; then
  # prompt 2048 and gen 400 mirror the repo harness; f16 and q8_0 KV; default and 2048 micro-batch
  "$D"/llama-bench -m "$BLOB" -ngl 999 -fa on -lm none -p 2048 -n 400 -r 3 -ctk f16,q8_0 -ctv f16,q8_0 -ub 512,2048 -b 2048 2>&1 | grep -E '^\||build'
else
  exec "$D"/llama-server -m "$BLOB" -ngl 999 -fa on -c 32768 -b 2048 -ub 2048 --load-mode none --host 127.0.0.1 --port 8099 --jinja
fi
