#!/usr/bin/env bash
set -euo pipefail

# Vicinae toggle + preflight for Hypr binds and Waybar icon
# - keeps the theme symlinked into ~/.local/share/vicinae/themes
# - ensures the server is running and the desired theme is active

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
theme_src="${base_dir}/amethyst-glass-vk.toml"
theme_dest="${HOME}/.local/share/vicinae/themes/amethyst-glass-vk.toml"

mkdir -p "$base_dir" "$(dirname "$theme_dest")"

if [[ ! -e "$theme_src" ]]; then
  echo "Vicinae theme missing at ${theme_src}" >&2
fi

# keep the shared theme path pointing at our curated palette
if [[ ! -e "$theme_dest" || "$(readlink -f "$theme_dest")" != "$(readlink -f "$theme_src")" ]]; then
  ln -sf "$theme_src" "$theme_dest"
fi

# light retry to wake the server before toggling
tries=0
until vicinae ping >/dev/null 2>&1 || [[ $tries -ge 3 ]]; do
  vicinae server --replace >/dev/null 2>&1 || true
  sleep 0.2
  tries=$((tries + 1))
done

if vicinae ping >/dev/null 2>&1; then
  vicinae theme set amethyst-glass-vk >/dev/null 2>&1 || true
elif [[ $ensure_only -eq 0 ]]; then
  vicinae server --replace --open >/dev/null 2>&1 || true
fi

if [[ $ensure_only -eq 1 ]]; then
  exit 0
fi

# toggle is idempotent when the window is open/closed already
vicinae toggle >/dev/null 2>&1 || vicinae open >/dev/null 2>&1 || true
