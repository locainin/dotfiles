#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# Waybar notifications helper for UnixNotis.
# - One-shot output avoids long-lived child processes in Waybar.
# - Active count is sourced from noticenterctl and rendered as JSON.
# - The bell glyph uses a JSON unicode escape to keep the script ASCII-only.

readonly ICON_BELL="\\uf0a2"

emit_json() {
  local text="$1"
  local tooltip="$2"
  local class="$3"
  printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class"
}

resolve_ctl() {
  if [[ -n "${NOTICENTERCTL:-}" && -x "$NOTICENTERCTL" ]]; then
    printf '%s' "$NOTICENTERCTL"
    return 0
  fi
  if command -v noticenterctl >/dev/null 2>&1; then
    command -v noticenterctl
    return 0
  fi
  if [[ -x "$HOME/.local/bin/noticenterctl" ]]; then
    printf '%s' "$HOME/.local/bin/noticenterctl"
    return 0
  fi
  return 1
}

count_active() {
  local ctl="$1"
  local output count
  output="$("$ctl" list-active 2>/dev/null || true)"
  count="$(printf '%s\n' "$output" | awk -F': ' '/^active notifications:/{print $2; exit}')"
  if [[ -z "$count" || ! "$count" =~ ^[0-9]+$ ]]; then
    count=0
  fi
  printf '%s' "$count"
}

format_payload() {
  local count="$1"
  local text="$ICON_BELL"
  local classes="bell"
  if (( count > 0 )); then
    text="$ICON_BELL $count"
    classes="bell unread"
  fi
  emit_json "$text" "Notifications: $count" "$classes"
}

main() {
  local action="${1:-once}"
  local ctl

  if ! ctl="$(resolve_ctl)"; then
    emit_json "$ICON_BELL" "Notifications: 0" "bell"
    return 0
  fi

  case "$action" in
    once)
      format_payload "$(count_active "$ctl")"
      ;;
    toggle-dnd)
      "$ctl" dnd toggle >/dev/null 2>&1 || true
      ;;
    *)
      printf 'Usage: unixnotis-notifications.sh [once|toggle-dnd]\n' >&2
      return 1
      ;;
  esac
}

main "$@"
