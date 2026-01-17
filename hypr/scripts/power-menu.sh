#!/usr/bin/env bash
set -euo pipefail

# launch a simple power menu; invoked via Waybar custom/power tile
# prefers wleave or nwg-bar, falls back to rofi/wofi dmenu

have() { command -v "$1" >/dev/null 2>&1; }

# prefer dedicated logout UIs
if have wleave; then
  # Use a local layout/css when present; otherwise fall back to defaults.
  layout="$HOME/.config/hypr/wleave/layout.json"
  css="$HOME/.config/hypr/wleave/style.css"
  if [ -f "$layout" ] && [ -f "$css" ]; then
    setsid -f wleave --layout "$layout" --css "$css" >/dev/null 2>&1 &
  else
    setsid -f wleave >/dev/null 2>&1 &
  fi
  exit 0
fi
if have nwg-bar; then
  setsid -f nwg-bar >/dev/null 2>&1 &
  exit 0
fi

run_action() {
  case "$1" in
    Shutdown)
      systemctl poweroff ;;
    Reboot)
      systemctl reboot ;;
    Suspend)
      systemctl suspend ;;
    Logout)
      hyprctl dispatch exit ;;
    Lock)
      if ! have swaylock && ! have gtklock && ! have hyprlock; then
        notify-send "No lock utility found" "Install swaylock, gtklock, or hyprlock" >/dev/null 2>&1 || true
        return
      fi
      if have swaylock; then
        swaylock
      elif have gtklock; then
        gtklock
      elif have hyprlock; then
        hyprlock
      fi
      ;;
  esac
}

options=("Shutdown" "Reboot" "Suspend" "Logout" "Lock")

if have rofi; then
  choice=$(printf '%s\n' "${options[@]}" | rofi -dmenu -i -p 'Power') || exit 1
  [ -n "$choice" ] && run_action "$choice"
elif have wofi; then
  choice=$(printf '%s\n' "${options[@]}" | wofi --dmenu --prompt 'Power') || exit 1
  [ -n "$choice" ] && run_action "$choice"
else
  # last resort: pick the safest default (nothing) but notify
  notify-send "Power menu not available" "Install wleave or nwg-bar" || true
  exit 127
fi
