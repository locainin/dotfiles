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

compute_newval() {
  python3 - "$action" "$current" "$DEFAULT" "$STEP" "$MIN" "$MAX" "${2-}" <<'PY'
import sys

action, current, default, step, minv, maxv, raw = (sys.argv[1:] + [""])[:7]

def f(x: str) -> float:
    return float(x)

cur = f(current)
default_f = f(default)
step_f = f(step)
min_f = f(minv)
max_f = f(maxv)

if action == "up":
    out = min(cur + step_f, max_f)
elif action == "down":
    out = max(cur - step_f, min_f)
elif action == "reset":
    out = default_f
elif action == "set":
    out = f(raw) if raw else default_f
    out = min(max(out, min_f), max_f)
else:
    raise SystemExit(2)

# Ensure stable formatting for kitty (avoid scientific notation).
print(f"{out:.10g}")
PY
}

case "$action" in
  up)
    newval="$(compute_newval)"
    ;;
  down)
    newval="$(compute_newval)"
    ;;
  reset)
    newval="$(compute_newval)"
    ;;
  set)
    # usage: font-zoom.sh set <value>
    newval="$(compute_newval "${2-}")"
    ;;
  *)
    echo "Unknown action: $action" >&2
    exit 2
    ;;
esac

# apply absolute size via RC
# Prefer kitty's own CLI. Fall back to the standalone kitten executable if present.
kitty @ set-font-size "$newval" >/dev/null 2>&1 || kitten @ set-font-size "$newval" >/dev/null 2>&1 || true

exit 0
