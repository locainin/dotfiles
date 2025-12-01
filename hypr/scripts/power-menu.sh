#!/usr/bin/env bash
set -euo pipefail

# launch a simple power menu; invoked via Waybar custom/power tile and launchers
# - prefers wleave or nwg-bar for a full-screen power UI
# - falls back to rofi/wofi dmenu with basic actions

have() { command -v "$1" >/dev/null 2>&1; }

# prefer dedicated logout UIs
if have wleave; then
  # use our layout/css so Logout calls hyprctl dispatch exit
  setsid -f wleave \
    --layout "$HOME/.config/hypr/wleave/layout.json" \
    --css "$HOME/.config/hypr/wleave/style.css" \
    >/dev/null 2>&1 &
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
      if have swaylock; then
        swaylock
      elif have gtklock; then
        gtklock
      elif have hyprlock; then
        hyprlock
      else
        notify-send "No lock utility found" "Install swaylock or gtklock" || true
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
