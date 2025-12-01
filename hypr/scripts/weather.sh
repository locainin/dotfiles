#!/usr/bin/env bash
set -euo pipefail

# simple weather helper for Waybar custom/weather drawer tile
# - uses wttr.in and prints a tiny JSON payload {"text": "..."}
# - location is configured via $WAYBAR_WEATHER_LOCATION
#   (e.g. "City, State") 

cache_file="${HOME}/.cache/waybar_weather"    # fallback cache used when network calls fail
mkdir -p "$(dirname "$cache_file")"
location="${WAYBAR_WEATHER_LOCATION:-""}"     # expects a URL-safe location string, e.g. "City+Country"

if [ -z "$location" ]; then
  # no location configured; keep output explicit so users know how to enable weather
  text="Set WAYBAR_WEATHER_LOCATION for weather"
  safe_text="$(printf '%s' "$text" | sed 's/\\/\\\\/g; s/\"/\\\"/g')"
  printf '{"text":"%s"}\n' "$safe_text"
  exit 0
fi

primary="$(curl -m 6 -s "http://wttr.in/${location}?format=3" || true)"

if [[ "$primary" =~ ^([^:]+):[[:space:]]*(.+)$ ]]; then
  weather="${BASH_REMATCH[2]}"
else
  weather="N/A"
fi

weather="${weather//+/}"                          # drop plus signs
weather="$(printf '%s' "$weather" | tr -s ' ')"   # normalize spaces

text="Weather: $weather"

if [[ "$weather" != "N/A" ]]; then
  printf '%s' "$text" > "$cache_file"
elif [[ -f "$cache_file" ]]; then
  text="$(cat "$cache_file")"
fi

safe_text="$(printf '%s' "$text" | sed 's/\\\\/\\\\\\\\/g; s/\"/\\\"/g')"

printf '{"text":"%s"}\n' "$safe_text"
