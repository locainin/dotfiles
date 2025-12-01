#!/usr/bin/env bash
set -euo pipefail

# brightness helper shared between Hyprland keybinds and Waybar backlight module
# - keeps keyboard brightness keys and Waybar scroll actions in sync

dev="${BRIGHTNESS_DEVICE:-intel_backlight}"
op="${1:-up}"
step="${2:-5}"

[[ "$step" =~ ^[0-9]+$ ]] || { echo "invalid step: $step" >&2; exit 2; }

sys="/sys/class/backlight/$dev"   # backlight device sysfs path
[[ -r "$sys/brightness" && -r "$sys/max_brightness" ]] || { echo "no backlight device: $dev" >&2; exit 1; }

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
