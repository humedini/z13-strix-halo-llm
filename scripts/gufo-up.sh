#!/bin/bash
# Qwen3.8 Flash-Next (UD-Q4_K_XL) on 127.0.0.1:8099 under Gufo with MTP speculative decoding. See docs/14-gufo.md.
#   gufo-up.sh          start (refuses if the GPU is busy, e.g. a game is open)
#   gufo-up.sh down     stop
#   gufo-up.sh status   container state, last log lines
#   gufo-up.sh key      print the API key (Bearer token)
# MODELS must contain q38fn-q4/ with the four GGUF parts and the shared MTP head. Log: docker logs gufo-flash-next
set -uo pipefail
NAME=gufo-flash-next
IMG=ghcr.io/gufo-org/toolboxes/gufo-runtime:latest
MODELS=${MODELS:-$HOME/llama-vulkan/models}
KEYFILE=$HOME/.config/gufo/api-key
PORT=${PORT:-8099}
RENDER=$(getent group render | cut -d: -f3); VIDEO=$(getent group video | cut -d: -f3)

[ -s "$KEYFILE" ] || { mkdir -p "$(dirname "$KEYFILE")"; (umask 077; head -c 24 /dev/urandom | base64 | tr -d '/+=' > "$KEYFILE"); }
KEY=$(cat "$KEYFILE")

case "${1:-up}" in
  down)   docker rm -f $NAME >/dev/null 2>&1 && echo "  $NAME stopped" || echo "  $NAME was not running";;
  status) docker ps -a --filter name=^$NAME$ --format '  {{.Status}}' | grep . || echo "  $NAME not running"
          docker logs --tail 3 $NAME 2>&1 | sed 's/^/  /';;
  key)    echo "$KEY";;
  up)
    if docker ps --filter name=^$NAME$ -q | grep -q .; then echo "  $NAME already running"; exit 0; fi
    # never start over a game: wait up to a minute for the GPU to be under 15 percent busy
    for w in $(seq 1 30); do B=$(cat /sys/class/drm/card*/device/gpu_busy_percent | sort -n | tail -1); [ "${B:-0}" -le 15 ] && break; sleep 2; done
    [ "${B:-0}" -gt 15 ] && { echo "  GPU is busy ($B%), not starting"; exit 3; }
    if ss -ltn | grep -q ":$PORT "; then echo "  port $PORT already in use"; exit 4; fi
    docker rm -f $NAME >/dev/null 2>&1
    docker run -d --name $NAME --device /dev/kfd --device /dev/dri --group-add "$RENDER" --group-add "$VIDEO" --network host \
      -v "$MODELS":/models:ro --entrypoint /bin/gufo-server $IMG \
      serve --host 127.0.0.1 --port $PORT --api-key "$KEY" llm \
      -m /models/q38fn-q4/Qwen3.8-Flash-Next-UD-Q4_K_XL-00001-of-00004.gguf \
      --served-model-name qwen3.8-flash-next \
      --speculative mtp --mtp-model /models/q38fn-q4/mtp-Qwen3.8-Flash-Next-shared-Q8_0.gguf \
      -c 65536 --max-tokens 16384 --temperature 0.7 --top-p 0.8 --top-k 20 \
      >/dev/null || exit 1
    echo -n "  loading (about 40 s from NVMe)"
    for i in $(seq 1 60); do
      curl -s -m 2 -o /dev/null -H "Authorization: Bearer $KEY" http://127.0.0.1:$PORT/v1/models && { echo; echo "  up: http://127.0.0.1:$PORT/v1  model qwen3.8-flash-next"; exit 0; }
      docker ps --filter name=^$NAME$ -q | grep -q . || { echo; docker logs --tail 20 $NAME; exit 1; }
      echo -n .; sleep 3
    done
    echo; echo "  still not answering after 3 min, see: docker logs $NAME"; exit 1;;
  *) sed -n 2,8p "$0";;
esac
