#!/usr/bin/env bash
set -euo pipefail

# pacman updates helper for Waybar custom/updates module
# - prints JSON containing text, tooltip, and class
# - also emits a desktop notification if the count crosses a threshold

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
mkdir -p "$cache_dir"
state_file="$cache_dir/pacman-updates-last"   # last seen update count to rate-limit notifications
threshold=100                                 # only notify when crossing above this many updates

if command -v checkupdates >/dev/null 2>&1; then
  updates="$(checkupdates 2>/dev/null || true)"
else
  updates="$(pacman -Qu --quiet 2>/dev/null || true)"
fi

count=0
if [ -n "$updates" ]; then
  count="$(printf '%s\n' "$updates" | sed '/^\s*$/d' | wc -l | tr -d ' ')"
fi

if [ "$count" -gt 0 ]; then
  text=" $count"
  escaped_list="$(printf '%s\n' "$updates" | head -n 15 | sed 's/\\\\/\\\\\\\\/g; s/\"/\\\"/g; s/$/\\n/' | tr -d '\n')"
  tooltip="$(printf 'Updates (%s):\\n%s' "$count" "$escaped_list")"
  class="updates available"
else
  text=" 0"
  tooltip="No updates"
  class="updates none"
fi

last_count=0
if [ -f "$state_file" ]; then
  last_count="$(cat "$state_file" 2>/dev/null || echo 0)"
fi

if [ "$count" -gt "$threshold" ] && [ "$last_count" -le "$threshold" ]; then
  notify-send "Package Updates" "$count packages available" -u normal
fi

printf '%s' "$count" >"$state_file" 2>/dev/null || true

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class"
