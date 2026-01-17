#!/usr/bin/env bash
set -euo pipefail

# shared by binds.conf brightness keys and waybar/config.jsonc backlight scroll actions so both paths stay in sync
# device auto-detection keeps the script portable across intel/amdgpu/acpi drivers; override with BRIGHTNESS_DEVICE when needed
detect_device() {
  if command -v brightnessctl >/dev/null 2>&1; then
    # brightnessctl -l prints: Device 'intel_backlight' of class backlight:
    local candidate
    candidate=$(brightnessctl -l 2>/dev/null | awk -F"'" '/class backlight/ {print $2; exit}')
    if [[ -n "$candidate" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  fi
  if compgen -G "/sys/class/backlight/*" >/dev/null 2>&1; then
    basename /sys/class/backlight/* | head -n1
    return
  fi
  printf '%s\n' "intel_backlight"
}

dev="${BRIGHTNESS_DEVICE:-$(detect_device)}"
op="${1:-up}"
step="${2:-5}"

[[ "$step" =~ ^[0-9]+$ ]] || { echo "invalid step: $step" >&2; exit 2; }

sys="/sys/class/backlight/$dev"
[[ -r "$sys/brightness" && -r "$sys/max_brightness" ]] || { echo "no backlight device: $dev" >&2; exit 1; }
if ! command -v brightnessctl >/dev/null 2>&1 && [[ ! -w "$sys/brightness" ]]; then
  echo "brightnessctl missing and $sys/brightness not writable" >&2
  exit 1
fi

cur=$(<"$sys/brightness")
max=$(<"$sys/max_brightness")
cur=${cur//[^0-9]/}
max=${max//[^0-9]/}
(( max > 0 )) || { echo "bad max_brightness" >&2; exit 1; }

# round to nearest percent so repeated steps stay consistent
cur_pct=$(( (cur * 100 + max / 2) / max ))

case "$op" in
  up|down|set) ;;
  *) echo "usage: $0 [up|down|set] [step]" >&2; exit 2 ;;
esac

if [[ "$op" == "set" ]]; then
  tgt=$step
else
  (( step > 0 )) || { echo "step must be greater than zero for $op" >&2; exit 2; }

  current_steps=$(( (cur_pct + step / 2) / step ))
  if [[ "$op" == "up" ]]; then
    target_steps=$(( current_steps + 1 ))
  else
    target_steps=$(( current_steps - 1 ))
  fi

  (( target_steps < 0 )) && target_steps=0
  max_steps=$(( (100 + step - 1) / step ))
  (( target_steps > max_steps )) && target_steps=max_steps

  tgt=$(( target_steps * step ))
fi

(( tgt < 0 )) && tgt=0
(( tgt > 100 )) && tgt=100

raw=$(( (tgt * max + 50) / 100 ))
(( raw < 0 )) && raw=0
(( raw > max )) && raw=$max

if command -v brightnessctl >/dev/null 2>&1; then
  brightnessctl -q -d "$dev" set "$raw"
else
  echo "$raw" > "$sys/brightness"
fi

echo "${tgt}% ($raw/$max) on $dev"
