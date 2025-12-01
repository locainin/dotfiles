#!/usr/bin/env bash
set -euo pipefail

# Waybar launcher for Hyprland
# - called from conf.d/waybar.conf, reload-all.sh, and launchers
# - prefers Hypr-local config under ~/.config/hypr/waybar, falls back to XDG waybar

logfile="/dev/null"
for candidate in "${XDG_CACHE_HOME:-$HOME/.cache}/hypr" "/tmp/hypr"; do
  mkdir -p "$candidate" 2>/dev/null || true
  if touch "$candidate/waybar.log" >/dev/null 2>&1; then
    logfile="$candidate/waybar.log"
    break
  fi
done

cfg="$HOME/.config/hypr/waybar/config.jsonc"; css="$HOME/.config/hypr/waybar/style.css"
cfg_wlr="$HOME/.config/waybar/config.wlr.jsonc"; css_std="$HOME/.config/waybar/style.css"

force_restart=false   # --restart flag forces a full restart instead of SIGUSR2 reload
while (($#)); do
  case "$1" in
    --force|--restart) force_restart=true ;;
  esac
  shift
done

if pgrep -x waybar >/dev/null 2>&1; then
  if [[ "$force_restart" == false ]]; then
    echo "[$(date +%F' '%T)] reloading existing waybar via SIGUSR2" >>"$logfile"
    pkill -USR2 waybar 2>/dev/null || true
    exit 0
  fi
  pkill -x waybar 2>/dev/null || true
  sleep 0.2
fi

echo "[$(date +%F' '%T)] starting waybar primary cfg=$cfg" >>"$logfile"
setsid -f waybar -c "$cfg" -s "$css" >>"$logfile" 2>&1 || true
sleep 1.2
if ! pgrep -x waybar >/dev/null 2>&1; then
  # fallback to wlr workspaces if hypr modules missing
  if [[ -f "$cfg_wlr" ]]; then
    echo "[$(date +%F' '%T)] waybar not running, trying fallback cfg=$cfg_wlr" >>"$logfile"
    setsid -f waybar -c "$cfg_wlr" -s "$css_std" >>"$logfile" 2>&1 || true
  fi
fi

exit 0
