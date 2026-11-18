#!/bin/bash
# ComfyUI on gfx1151, loopback only. See docs/15-comfyui.md.
# usage: comfyui-start.sh [stop]     COMFY_DIR = ComfyUI checkout with its venv, PORT default 8189
cd "${COMFY_DIR:-$HOME/ComfyUI}" || exit 1
PORT=${PORT:-8189}
for p in $(pgrep -x python); do grep -qa -- "main.py.--listen.127.0.0.1.--port.$PORT" /proc/$p/cmdline 2>/dev/null && kill $p; done
[ "${1:-}" = stop ] && { echo stopped; exit 0; }
sleep 2
# ComfyUI turns MIOpen off on RDNA3+, and torch's native bf16 Conv3d then segfaults on gfx1151 (Qwen3-VL patch embed, image edit)
export COMFYUI_ENABLE_MIOPEN=1 MIOPEN_FIND_MODE=FAST   # FAST skips the per-shape kernel search (minutes per new image size)
nohup venv/bin/python main.py --listen 127.0.0.1 --port $PORT --disable-mmap --disable-pinned-memory --reserve-vram 4 >> comfy.log 2>&1 &
for i in $(seq 1 60); do sleep 2; curl -s -m 2 http://127.0.0.1:$PORT/system_stats >/dev/null && { echo "ComfyUI up at http://127.0.0.1:$PORT"; exit 0; }; done
echo "did not come up, see comfy.log"; tail -5 comfy.log
