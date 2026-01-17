#!/usr/bin/env bash
set -euo pipefail

# one-key reload helper for the Hyprland stack
# - wired to binds.conf Ctrl+Shift+R and Vicinae powertools
# - reloads Hyprland, restarts Waybar + SwayNC, and nudges Vicinae

have() {
  command -v "$1" >/dev/null 2>&1
}

# 1) reload Hyprland config so layout/binds take effect
if have hyprctl;
  then
  hyprctl reload || true
fi

# brief pause to let Hyprland apply changes
sleep 0.15

# 2) restart panels/daemons in use
pkill -x quickshell 2>/dev/null || true
if [ -x "$HOME/.config/hypr/scripts/start-waybar.sh" ]; then
  "$HOME/.config/hypr/scripts/start-waybar.sh" --restart
elif have waybar; then
  pkill -x waybar 2>/dev/null || true
  setsid -f waybar >/dev/null 2>&1 || true
fi

if [ -x "$HOME/.config/hypr/scripts/start-swaync.sh" ]; then
  systemctl --user stop mako.service >/dev/null 2>&1 || true
  pkill -x mako 2>/dev/null || true
  pkill -9 -f swaync 2>/dev/null || true
  sleep 0.5
  "$HOME/.config/hypr/scripts/start-swaync.sh" &
fi

# 3) close any open launchers so they reload config on next invoke
if have vicinae; then
  vicinae close >/dev/null 2>&1 || true
  vicinae server --replace >/dev/null 2>&1 || true
fi

# 4) optional notify to confirm completion
if have notify-send; then
  notify-send --expire-time=2500 --urgency=low \
    --hint=string:x-canonical-private-synchronous:hypr-reload \
    "!(Waybar, Hypr, Swaync, Vicinae. Have Been Reloaded)!" >/dev/null 2>&1 || true
fi

exit 0
