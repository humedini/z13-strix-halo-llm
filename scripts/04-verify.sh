#!/bin/bash
# Post-install verification. No root needed.
echo "=========== GZ302 / Strix Halo verification ==========="
echo
echo "--- Kernel / platform ---"
uname -r; cat /sys/class/dmi/id/product_name

echo
echo "--- GPU ---"
glxinfo -B 2>/dev/null | grep -E "OpenGL renderer|OpenGL core profile version" || echo "mesa-utils missing"
vulkaninfo --summary 2>/dev/null | grep -E "deviceName|driverName" || echo "vulkan-tools missing"

echo
echo "--- ROCm / gfx target ---"
rocminfo 2>/dev/null | grep -E "^\s+Name:\s+gfx|Marketing Name" | head -6 || echo "rocminfo missing"
echo "HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION:-<unset — correct for gfx1151>}"

echo
echo "--- NPU ---"
ls /dev/accel/ 2>/dev/null || echo "no /dev/accel"

echo
echo "--- ASUS control (native sysfs) ---"
for a in /sys/class/firmware-attributes/*/attributes/*/; do
  printf "  %-18s %s\n" "$(basename "$a")" "$(cat "$a/current_value" 2>/dev/null)"
done 2>/dev/null
echo "  platform_profile   $(cat /sys/firmware/acpi/platform_profile 2>/dev/null)"
echo "  --- live values (asus-nb-wmi; the armoury values above can be stale) ---"
for f in ppt_pl1_spl ppt_pl2_sppt ppt_fppt; do
  printf "  live %-16s %s W\n" "$f" "$(cat /sys/devices/platform/asus-nb-wmi/$f 2>/dev/null)"
done
echo "  charge limit       $(cat /sys/class/power_supply/BAT0/charge_control_end_threshold 2>/dev/null)"

echo
echo "--- z13ctl / command center ---"
command -v z13ctl >/dev/null && echo "  z13ctl: $(z13ctl --version 2>/dev/null || echo installed)" || echo "  z13ctl: not installed"
command -v pwrcfg >/dev/null && echo "  pwrcfg: installed" || echo "  pwrcfg: not installed"

echo
echo "--- Memory split ---"
echo "  VRAM:  $(( $(cat /sys/class/drm/card*/device/mem_info_vram_total 2>/dev/null | head -1) / 1024/1024/1024 )) GiB"
echo "  RAM:   $(free -g | awk '/Mem:/{print $2}') GiB"

echo
echo "--- Thermals / fans ---"
sensors 2>/dev/null | grep -E "fan|Tctl|edge|junction" || echo "  lm-sensors missing"

echo
echo "--- LLM backends ---"
for b in ollama llama-cli llama-server; do
  command -v $b >/dev/null && echo "  ✓ $b" || echo "  ✗ $b"
done
[[ -d "$HOME/.strix-halo-ai" ]] && echo "  ✓ python AI venv (~/.strix-halo-ai)" || echo "  ✗ python AI venv"
