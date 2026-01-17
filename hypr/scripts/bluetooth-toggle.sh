#!/usr/bin/env bash
set -euo pipefail

state_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
state_file="$state_dir/bluetooth.power"
mkdir -p "$state_dir" 2>/dev/null || true

notify() {
  local msg="$1" ; local icon="${2:-bluetooth}"
  if command -v dunstify >/dev/null 2>&1; then
    dunstify -a "Bluetooth" -i "$icon" "$msg" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Bluetooth" -i "$icon" "$msg" >/dev/null 2>&1 || true
  fi
}

is_powered_on() {
  # “bluetoothctl show” exposes “Powered: yes/no”
  bluetoothctl show 2>/dev/null | grep -qi 'Powered:\s*yes'
}

# If rfkill has blocked the radio, unblock before power on
unblock_rfkill() {
  if command -v rfkill >/dev/null 2>&1 && rfkill list bluetooth 2>/dev/null | grep -qi 'Soft blocked: yes\|Hard blocked: yes'; then
    rfkill unblock bluetooth || true
    sleep 0.2
  fi
}

# Try to ensure daemon running (non-fatal if it isn't)
ensure_daemon() {
  systemctl is-active bluetooth.service >/dev/null 2>&1 || systemctl start bluetooth.service >/dev/null 2>&1 || true
}

if is_powered_on; then
  bluetoothctl power off >/dev/null 2>&1 || true
  if command -v rfkill >/dev/null 2>&1; then
    rfkill block bluetooth >/dev/null 2>&1 || true
  fi
  notify "Bluetooth: Off" "bluetooth-disabled"
  echo "off" >"$state_file" 2>/dev/null || true
else
  ensure_daemon
  if command -v rfkill >/dev/null 2>&1; then
    rfkill unblock bluetooth >/dev/null 2>&1 || true
  fi
  unblock_rfkill
  bluetoothctl power on  >/dev/null 2>&1 || true
  notify "Bluetooth: On"  "bluetooth"
  echo "on" >"$state_file" 2>/dev/null || true
fi

# Waybar's builtin bluetooth module listens on DBus and will refresh on its own
# (no SIGRTMIN needed for builtin modules)
