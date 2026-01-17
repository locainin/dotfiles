#!/usr/bin/env bash
set -euo pipefail

# Label toggles for the connected line.
# Shows the country portion of the location. Comment out to disable.

#show_country=1

# Shows the city portion of the location. Comment out to disable.

#show_city=1

# Shows the state or region portion of the location. Comment out to disable.

#show_state=1

# Shows the lock glyph. Comment out to disable.

show_lock=1

# feeds Waybar custom/mullvad plus click actions in config.jsonc to launch/toggle Mullvad quickly

timeout_tool="${TIMEOUT_BIN:-timeout}"

# ----- utilities -----
json() { # text, class, tooltip  (robust escaping for Waybar)
  local text="$1" cls="$2" tip="${3:-}"
  tip="${tip//\\/\\\\}"           # escape backslashes first
  tip="${tip//$'\n'/\\n}"         # turn real newlines into \n
  tip="${tip//$'\r'/}"            # strip CRs
  tip="${tip//\"/\\\"}"           # escape quotes
  printf '{"text":"%s","class":"%s","tooltip":"%s"}\n' "$text" "$cls" "$tip"
}

refresh_waybar() { pkill -SIGRTMIN+11 waybar >/dev/null 2>&1 || true; }

# ----- Wayland-friendly GUI launcher with logging & focus -----
launch_gui() {
  local logdir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
  mkdir -p "$logdir"
  local logfile="$logdir/mullvad-launch.log"

  (
    printf '[%s] launch attempt\n' "$(date +%F' '%T)"

    # focus existing Mullvad window if present
    if command -v hyprctl >/dev/null 2>&1 && hyprctl clients 2>/dev/null | grep -qi 'class:.*mullvad'; then
      if hyprctl dispatch focuswindow 'class:^(?i)mullvad.*' >/dev/null 2>&1; then
        printf '[%s] focused existing window via hyprctl\n' "$(date +%F' '%T)"
        exit 0
      fi
    fi

    # clean restart the GUI if it’s already running
    if pgrep -x mullvad-gui >/dev/null 2>&1 || pgrep -f "/opt/Mullvad VPN/mullvad-gui" >/dev/null 2>&1; then
      printf '[%s] mullvad-gui already running, restarting\n' "$(date +%F' '%T)"
      pkill -x mullvad-gui >/dev/null 2>&1 || pkill -f "/opt/Mullvad VPN/mullvad-gui" >/dev/null 2>&1 || true
      for _ in $(seq 1 20); do pgrep -x mullvad-gui >/dev/null 2>&1 || pgrep -f "/opt/Mullvad VPN/mullvad-gui" >/dev/null 2>&1 || break; sleep 0.1; done
      if pgrep -x mullvad-gui >/dev/null 2>&1 || pgrep -f "/opt/Mullvad VPN/mullvad-gui" >/dev/null 2>&1; then
        pkill -KILL -x mullvad-gui >/dev/null 2>&1 || pkill -KILL -f "/opt/Mullvad VPN/mullvad-gui" >/dev/null 2>&1 || true
        for _ in $(seq 1 10); do pgrep -x mullvad-gui >/dev/null 2>&1 || pgrep -f "/opt/Mullvad VPN/mullvad-gui" >/dev/null 2>&1 || break; sleep 0.1; done
      fi
    fi

    # preferred: direct GUI binary with Wayland flags
    if [[ -x "/opt/Mullvad VPN/mullvad-gui" ]]; then
      local -a gui_cmd=("/opt/Mullvad VPN/mullvad-gui" "--ozone-platform=wayland" "--enable-features=WaylandWindowDecorations")
      if setsid -f "${gui_cmd[@]}" >/dev/null 2>&1; then
        printf '[%s] launched via direct gui binary\n' "$(date +%F' '%T)"
        if command -v hyprctl >/dev/null 2>&1; then
          for _ in $(seq 1 20); do
            if hyprctl clients 2>/dev/null | grep -qi 'class:.*mullvad'; then
              hyprctl dispatch focuswindow 'class:^(?i)mullvad.*' >/dev/null 2>&1 || true
              break
            fi
            sleep 0.1
          done
        fi
        exit 0
      fi
    fi

    # fallbacks: wrapper, PATH binary, desktop launchers
    if [[ -x "/opt/Mullvad VPN/mullvad-vpn" ]] && setsid -f "/opt/Mullvad VPN/mullvad-vpn" >/dev/null 2>&1; then
      printf '[%s] launched via direct wrapper\n' "$(date +%F' '%T)"; exit 0
    fi
    if command -v mullvad-vpn >/dev/null 2>&1 && setsid -f mullvad-vpn >/dev/null 2>&1; then
      printf '[%s] launched via PATH mullvad-vpn\n' "$(date +%F' '%T)"; exit 0
    fi
    if command -v gtk-launch >/dev/null 2>&1 && gtk-launch mullvad-vpn >/dev/null 2>&1; then
      printf '[%s] launched via gtk-launch\n' "$(date +%F' '%T)"; exit 0
    fi
    if command -v xdg-open >/dev/null 2>&1 && [[ -f /usr/share/applications/mullvad-vpn.desktop ]]; then
      if xdg-open /usr/share/applications/mullvad-vpn.desktop >/dev/null 2>&1; then
        printf '[%s] launched via xdg-open\n' "$(date +%F' '%T)"; exit 0
      fi
    fi

    printf '[%s] launch failed\n' "$(date +%F' '%T)"
  ) >>"$logfile" 2>&1 &
}

# ----- helpers for status parsing -----
mullvad_status() {
  if command -v "$timeout_tool" >/dev/null 2>&1; then
    "$timeout_tool" 5 mullvad status 2>/dev/null || true
  else
    mullvad status 2>/dev/null || true
  fi
}

connected_now() { mullvad_status | grep -qi '^Connected'; }

sanitize_status() {
  printf '%s' "$1" | sed -E 's/[0-9]{1,3}(\.[0-9]{1,3}){3}//g; s/IPv[0-9]+:[[:space:]]*//g; s/[[:space:]]{2,}/ /g'
}

trim_ws() {
  # Normalizes labels for consistent formatting.
  printf '%s' "$1" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//'
}

visible_location_from_status() {
  local s="$1" line loc
  if line=$(printf '%s\n' "$s" | grep -i 'Visible location'); then
    loc=${line#*:}
  elif line=$(printf '%s\n' "$s" | grep -i '^[[:space:]]*Relay:'); then
    loc=${line#*:}
  else
    printf 'Unknown'
    return
  fi

  loc=$(printf '%s' "$loc" | sed -E '
    s/^[[:space:]]+//;
    s/[[:space:]]+$//;
    s/^\.+//;
    s/\([^)]*\)//g;
    s/[0-9]{1,3}(\.[0-9]{1,3}){3}//g;
    s/\[[0-9A-Fa-f:]+\]//g;
    s/@[0-9A-Za-z._:-]+//g;
    s/IPv[0-9]+:[[:space:]]*//g;
    s/[[:space:]]{2,}/ /g
  ')

  if [[ -z "$loc" ]]; then
    printf 'Unknown'
  else
    printf '%s' "$loc"
  fi
}

format_location() {
  # Formats the location segment based on the toggles.
  local loc="$1"
  local country city region out

  IFS=',' read -r country city region <<< "$loc"

  country="$(trim_ws "$country")"
  city="$(trim_ws "$city")"
  region="$(trim_ws "$region")"

  out=""

  if [[ "${show_country:-0}" == "1" && -n "$country" ]]; then
    out="$country"
  fi

  if [[ "${show_city:-0}" == "1" && -n "$city" ]]; then
    if [[ -n "$out" ]]; then
      out="$out, $city"
    else
      out="$city"
    fi
  fi

  if [[ "${show_state:-0}" == "1" && -n "$region" ]]; then
    if [[ -n "$out" ]]; then
      out="$out, $region"
    else
      out="$region"
    fi
  fi

  if [[ -z "$out" && -n "$loc" && ( "${show_city:-0}" == "1" || "${show_state:-0}" == "1" ) ]]; then
    out="$loc"
  fi

  printf '%s' "$out"
}

notify() {
  local msg="$1"
  if command -v dunstify >/dev/null 2>&1; then
    dunstify -a "Mullvad" -i network-vpn "$msg" >/dev/null 2>&1 || true
  elif command -v notify-send >/dev/null 2>&1; then
    notify-send -a "Mullvad" -i network-vpn "$msg" >/dev/null 2>&1 || true
  fi
}

# ----- click actions -----
case "${1:-}" in
  --launch) launch_gui; exit 0 ;;
  --toggle)
    if connected_now; then mullvad disconnect >/dev/null 2>&1 || true; notify "VPN: Disconnected"
    else mullvad connect >/dev/null 2>&1 || true; notify "VPN: Connected"; fi
    sleep 0.3; refresh_waybar; exit 0 ;;
  --up)   mullvad connect    >/dev/null 2>&1 || true; notify "VPN: Connected";    sleep 0.2; refresh_waybar; exit 0 ;;
  --down) mullvad disconnect >/dev/null 2>&1 || true; notify "VPN: Disconnected"; sleep 0.2; refresh_waybar; exit 0 ;;
esac

# ----- display path -----
if ! command -v mullvad >/dev/null 2>&1; then
  json " Disconnected" "disconnected" "Mullvad CLI not found"
  exit 0
fi

status_raw="$(mullvad_status)"

if [[ -z "$status_raw" ]]; then
  json "󰇚 Checking…" "connecting" "Waiting for Mullvad daemon response"
  exit 0
fi

if echo "$status_raw" | grep -qi '^Connected'; then
  loc_display="Connected"
  if [[ "${show_country:-0}" == "1" || "${show_city:-0}" == "1" || "${show_state:-0}" == "1" ]]; then
    loc="$(visible_location_from_status "$status_raw")"
    loc_display="$(format_location "$loc")"
    [[ -z "$loc_display" ]] && loc_display="Connected"
  fi
  if [[ "${show_lock:-0}" == "1" ]]; then
    loc_display=" $loc_display"
  fi
  json "$loc_display" "connected" "$(sanitize_status "$status_raw")"
elif echo "$status_raw" | grep -qi 'Connecting\|Reconnecting'; then
  json "󰇚 Connecting…" "connecting" "$(sanitize_status "$status_raw")"
else
  json " Disconnected" "disconnected" "$(sanitize_status "$status_raw")"
fi
