#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# UnixNotis panel toggle helper for Waybar.
# - Keeps Waybar click handlers decoupled from hard-coded binary locations.
# - Falls back to repo build outputs for local development.

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

main() {
  local ctl
  if ! ctl="$(resolve_ctl)"; then
    printf 'noticenterctl not found; ensure it is installed or built.\n' >&2
    return 1
  fi
  "$ctl" toggle-panel
}

main "$@"
