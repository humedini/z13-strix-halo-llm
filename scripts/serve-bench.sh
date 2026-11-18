#!/bin/bash
# usage: serve-bench.sh LABEL -- <llama-server args...>
# Starts llama-server (Vulkan) on 127.0.0.1:8099, runs bench-openai.py, stops the server. See docs/13-vulkan.md and 14-gufo.md.
# LLAMA_DIR = unpacked bNNNN Vulkan release; UB = micro-batch (default 2048). Refuses to start if the GPU is busy.
D=${LLAMA_DIR:-$HOME/llama-vulkan/b10964}; export LD_LIBRARY_PATH=$D; LABEL=$1; shift 2
HERE=$(dirname "$(readlink -f "$0")"); LOG=${TMPDIR:-/tmp}/server-$LABEL.log
for w in $(seq 1 30); do B=$(cat /sys/class/drm/card*/device/gpu_busy_percent | sort -n | tail -1); [ "${B:-0}" -le 15 ] && break; sleep 2; done; [ "${B:-0}" -gt 15 ] && { echo "GPU is busy ($B%), not starting"; exit 3; }
pgrep -x llama-server >/dev/null && { echo "a llama-server is already running"; exit 1; }
setsid nohup "$D"/llama-server "$@" -ngl 999 -fa on -c 32768 -b 2048 -ub ${UB:-2048} --load-mode none --host 127.0.0.1 --port 8099 --jinja > "$LOG" 2>&1 < /dev/null &
for i in $(seq 1 600); do sleep 2; pgrep -x llama-server >/dev/null || { echo "server exited"; grep -iE ' E |error' "$LOG" | head -5; exit 1; }; [ "$(curl -s http://127.0.0.1:8099/health | grep -c '"ok"')" = 1 ] && break; done
echo "== $LABEL  (loaded in $((i*2))s, $(free -g | awk 'NR==2{print "avail "$7" GiB"}')) =="
python3 "$HERE"/bench-openai.py http://127.0.0.1:8099/v1 "$LABEL" 3 2>&1 | tail -4
grep -E 'draft acceptance|acceptance rate' "$LOG" | tail -2
kill $(pgrep -x llama-server); for i in $(seq 1 30); do pgrep -x llama-server >/dev/null || break; sleep 1; done
