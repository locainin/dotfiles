#!/usr/bin/env bash
set -euo pipefail

# Vicinae toggle + preflight for Hypr binds and Waybar icon
# - ensures the server is running before we toggle/open the palette

ensure_only=0
if [[ "${1-}" == "--ensure" ]]; then
  ensure_only=1
  shift || true
fi

if ! command -v vicinae >/dev/null 2>&1; then
  echo "vicinae binary not found in PATH" >&2
  exit 1
fi

# light retry to wake the server before toggling
tries=0
until vicinae ping >/dev/null 2>&1 || [[ $tries -ge 3 ]]; do
  vicinae server --replace >/dev/null 2>&1 || true
  sleep 0.2
  tries=$((tries + 1))
done

if ! vicinae ping >/dev/null 2>&1 && [[ $ensure_only -eq 0 ]]; then
  vicinae server --replace --open >/dev/null 2>&1 || true
fi

if [[ $ensure_only -eq 1 ]]; then
  exit 0
fi

# toggle is idempotent when the window is open/closed already
vicinae toggle >/dev/null 2>&1 || vicinae open >/dev/null 2>&1 || true
