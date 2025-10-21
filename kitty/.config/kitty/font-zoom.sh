#!/usr/bin/env bash
# bounded font zoom helper for kitty (uses remote control)
# honors env defaults from kitty.conf: KITTY_FONT_DEFAULT, KITTY_FONT_MAX, KITTY_FONT_MIN, KITTY_FONT_STEP

set -euo pipefail

DEFAULT="${KITTY_FONT_DEFAULT:-11.5}"
MAX="${KITTY_FONT_MAX:-12.0}"
MIN="${KITTY_FONT_MIN:-9.0}"
STEP="${KITTY_FONT_STEP:-0.5}"

action="${1:-up}"

# query current effective font size via query_terminal kitten
current=$(kitty +kitten query_terminal font_size 2>/dev/null | awk -F': ' '/font_size/{print $2}') || true
if [[ -z "${current:-}" ]]; then
  current="$DEFAULT"
fi

clamp() {
  python3 - <<PY
v = float(${1})
lo = float(${2})
hi = float(${3})
print(max(lo, min(v, hi)))
PY
}

case "$action" in
  up)
    newval=$(python3 - <<PY
v = float("$current"); s = float("$STEP"); m = float("$MAX")
nv = v + s
print(nv if nv <= m else m)
PY
)
    ;;
  down)
    newval=$(python3 - <<PY
v = float("$current"); s = float("$STEP"); m = float("$MIN")
nv = v - s
print(nv if nv >= m else m)
PY
)
    ;;
  reset)
    newval="$DEFAULT"
    ;;
  set)
    # usage: font-zoom.sh set <value>
    newval="${2:-$DEFAULT}"
    ;;
  *)
    echo "Unknown action: $action" >&2
    exit 2
    ;;
esac

# apply absolute size via RC
kitten @ set-font-size "$newval" >/dev/null 2>&1 || kitty @ set-font-size "$newval" >/dev/null 2>&1 || true

exit 0
