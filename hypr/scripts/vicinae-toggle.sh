#!/usr/bin/env bash
set -euo pipefail

# Vicinae toggle + preflight for Hypr binds/Waybar; optional theme handling stays resilient
# login path avoids tight restart loops so upstream crashes cannot spam multiple core dumps

ensure_only=0
if [[ "${1-}" == "--ensure" ]]; then
  ensure_only=1
  shift || true
fi

if ! command -v vicinae >/dev/null 2>&1; then
  echo "vicinae binary not found in PATH" >&2
  exit 1
fi

base_dir="${HOME}/.config/hypr/vicinae"
theme_name="${VICINAE_THEME:-vicinae-dark}"
theme_src="${base_dir}/${theme_name}.toml"
theme_dest="${HOME}/.local/share/vicinae/themes/${theme_name}.toml"

# Create the theme paths only when a local theme exists.
if [[ -f "$theme_src" ]]; then
  mkdir -p "$base_dir" "$(dirname "$theme_dest")"
  if [[ ! -e "$theme_dest" || "$(readlink -f "$theme_dest")" != "$(readlink -f "$theme_src")" ]]; then
    ln -sf "$theme_src" "$theme_dest"
  fi
fi

# single gentle wakeup to avoid multiple crashing server attempts
if ! vicinae ping >/dev/null 2>&1; then
  vicinae server --replace >/dev/null 2>&1 || true
fi

if vicinae ping >/dev/null 2>&1; then
  # Theme setting is best-effort; failures fall back to Vicinae defaults.
  if [[ -n "${theme_name:-}" ]]; then
    vicinae theme set "$theme_name" >/dev/null 2>&1 || true
  fi
fi

if [[ $ensure_only -eq 0 ]]; then
  # toggle is idempotent when the window is open/closed already; fallback open keeps first launch smooth
  vicinae toggle >/dev/null 2>&1 || vicinae open >/dev/null 2>&1 || true
fi
