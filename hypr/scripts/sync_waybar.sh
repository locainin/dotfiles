#!/usr/bin/env bash
set -euo pipefail

# one-shot helper to sync Hypr Waybar config into XDG waybar dir
# - copies ~/.config/hypr/waybar/{config.jsonc,style.css} to ~/.config/waybar
# - backs up any existing ~/.config/waybar to ~/.config/waybar.backup.TIMESTAMP

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)
hypr_root=$(cd -- "$script_dir/.." && pwd -P)
src="$hypr_root/waybar"
dst="$HOME/.config/waybar"

if [[ ! -d "$src" ]]; then
  echo "source waybar dir not found: $src" >&2
  exit 1
fi

mkdir -p "$HOME/.config"
if [[ -d "$dst" && ! -L "$dst" ]]; then
  ts=$(date +%Y%m%d-%H%M%S)
  mv "$dst"{"",.backup."$ts"}
fi

mkdir -p "$dst"
cp -f "$src"/config.jsonc "$dst/"
cp -f "$src"/style.css "$dst/"

echo "Synced Waybar config to $dst"
