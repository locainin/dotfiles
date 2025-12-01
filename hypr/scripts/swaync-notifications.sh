#!/usr/bin/env bash
set -euo pipefail

# swaync notification count + DND helper for Waybar custom/notifications
# - prints JSON with text/tooltip/class for the notification bell
# - supports click actions to toggle DND and request a refresh

action="${1-}"

refresh() {
  get_val() {
    if command -v swaync-client >/dev/null 2>&1; then
      timeout 1 swaync-client "$@" 2>/dev/null || true
    fi
  }

  count="$(get_val -c)"
  dnd="$(get_val -D)"

  if [ -z "$count" ]; then
    count=0
  fi
  if [ -z "$dnd" ]; then
    dnd=false
  fi

  icon=""
  class="bell"

  if [ "$dnd" = "true" ]; then
    icon=""
    class="dnd"
  fi

  if [ "${count:-0}" -gt 0 ]; then
    class="$class unread"
    icon="$icon $count"
  fi

  tooltip="Notifications: ${count:-0}"
  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$icon" "$tooltip" "$class"
}

case "$action" in
  toggle-dnd)
    swaync-client -d >/dev/null 2>&1 || true
    pkill -RTMIN+10 waybar || true
    ;;
  refresh)
    pkill -RTMIN+10 waybar || true
    ;;
  *)
    refresh
    ;;
esac
