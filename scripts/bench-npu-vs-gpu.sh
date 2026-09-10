#!/bin/bash
# Samples APU package power while a benchmark runs, so NPU vs GPU efficiency
# is measured rather than quoted.
# Usage: bench-npu-vs-gpu.sh <label> <command...>
LABEL="$1"; shift
P=$(for h in /sys/class/hwmon/hwmon*; do [ "$(cat $h/name 2>/dev/null)" = "amdgpu" ] && echo $h/power1_average; done | head -1)
SAMPLES=$(mktemp)
( while :; do cat "$P" 2>/dev/null >> "$SAMPLES"; sleep 1; done ) &
SAMPLER=$!
"$@"
RC=$?
kill $SAMPLER 2>/dev/null; wait $SAMPLER 2>/dev/null
echo
python3 - "$SAMPLES" "$LABEL" << 'PY'
import sys
vals=[int(l)/1e6 for l in open(sys.argv[1]) if l.strip().isdigit()]
if vals:
    vals=vals[2:] if len(vals)>4 else vals   # drop ramp-up
    print(f"  [{sys.argv[2]}] APU power: mean {sum(vals)/len(vals):.1f} W   peak {max(vals):.1f} W   samples {len(vals)}")
else:
    print(f"  [{sys.argv[2]}] no power samples")
PY
rm -f "$SAMPLES"
exit $RC
