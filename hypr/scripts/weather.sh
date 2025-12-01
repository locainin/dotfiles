#!/usr/bin/env python3
"""
Waybar weather helper for Hypr setup
- Configure location via DEFAULT_LOCATION or WAYBAR_WEATHER_LOCATION env
- Toggle city label via DEFAULT_SHOW_CITY or WAYBAR_WEATHER_SHOW_CITY=0/1
- Prints a tiny JSON payload {"text": "..."} for Waybar custom/weather
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime
from pathlib import Path

# ----------------------------
# user-tunable defaults
# ----------------------------
# set to your preferred string, e.g. "City, State"
# env WAYBAR_WEATHER_LOCATION overrides this at runtime
DEFAULT_LOCATION = "City, State"
# set to True to show "City, State: <emoji> <temp>", False to hide the city label
# env WAYBAR_WEATHER_SHOW_CITY overrides this at runtime
DEFAULT_SHOW_CITY = True
# ----------------------------

# cache file keeps the last successful value so we can show something when offline
CACHE_PATH = Path(os.path.expanduser("~/.cache/waybar_weather"))
CACHE_PATH.parent.mkdir(parents=True, exist_ok=True)

# prefer explicit env location when set, otherwise fall back to DEFAULT_LOCATION
env_location = os.environ.get("WAYBAR_WEATHER_LOCATION", "").strip()
location_display = env_location if env_location else DEFAULT_LOCATION.strip()

# normalize show_city from env into a boolean, falling back to DEFAULT_SHOW_CITY
show_city_env = os.environ.get("WAYBAR_WEATHER_SHOW_CITY", "").strip().lower()
if show_city_env in {"1", "true", "yes"}:
    show_city = True
elif show_city_env in {"0", "false", "no"}:
    show_city = False
else:
    show_city = bool(DEFAULT_SHOW_CITY)


def emit(text: str) -> None:
    # emit minimal JSON with escaped text for Waybar custom module
    safe = text.replace("\\", "\\\\").replace('"', '\\"')
    sys.stdout.write(f'{{"text":"{safe}"}}\n')


def cache_write(text: str) -> None:
    # best-effort write; failures are non-fatal
    try:
        CACHE_PATH.write_text(text, encoding="utf-8")
    except OSError:
        pass


def cache_read() -> str | None:
    # read cached text if present so we can show it when API calls fail
    try:
        return CACHE_PATH.read_text(encoding="utf-8")
    except OSError:
        return None


# guard against placeholder location making accidental API calls
if not location_display or location_display.lower() == "city, state":
    emit("Set WAYBAR_WEATHER_LOCATION for weather")
    sys.exit(0)


def fetch_weather_json(encoded_loc: str) -> str:
    # ask wttr.in for compact JSON (j1) so we can inspect temp + astronomy
    url = f"https://wttr.in/{encoded_loc}?format=j1"
    try:
        with urllib.request.urlopen(url, timeout=8) as resp:
            return resp.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, TimeoutError, OSError):
        return ""


encoded_location = urllib.parse.quote_plus(location_display, safe=",")
raw_json = fetch_weather_json(encoded_location)

if not raw_json:
    cached = cache_read()
    emit(cached if cached else "Weather: N/A")
    sys.exit(0)

try:
    data = json.loads(raw_json)
except json.JSONDecodeError:
    cached = cache_read()
    emit(cached if cached else "Weather: N/A")
    sys.exit(0)

current = (data.get("current_condition") or [{}])[0]
weather = (data.get("weather") or [{}])[0]
astronomy = (weather.get("astronomy") or [{}])[0]

# core fields we care about for the widget
temp_f = str(current.get("temp_F", "")).strip()
condition = str((current.get("weatherDesc") or [{}])[0].get("value", "")).strip()
local_dt = str(current.get("localObsDateTime", "")).strip()
moon_phase = str(astronomy.get("moon_phase", "")).strip()

if temp_f == "":
    cached = cache_read()
    emit(cached if cached else "Weather: N/A")
    sys.exit(0)


def is_night_time(local_str: str) -> bool:
    # derive rough day vs night from localObsDateTime
    # wttr format example: "2025-12-01 12:35 AM"
    try:
        dt = datetime.strptime(local_str, "%Y-%m-%d %I:%M %p")
        hour = dt.hour
    except ValueError:
        return False
    return hour >= 20 or hour < 7


def moon_icon(phase: str) -> str:
    # map textual moon phase into a reasonably close unicode moon glyph
    pl = phase.lower()
    if "new" in pl:
        return "🌑"
    if "waxing crescent" in pl:
        return "🌒"
    if "first quarter" in pl:
        return "🌓"
    if "waxing gibbous" in pl:
        return "🌔"
    if "full" in pl:
        return "🌕"
    if "waning gibbous" in pl:
        return "🌖"
    if "last quarter" in pl or "third quarter" in pl:
        return "🌗"
    if "waning crescent" in pl:
        return "🌘"
    return "🌙"


def condition_icon(desc: str, night: bool) -> str:
    # pick a single emoji based on condition keywords and whether it is night
    # clear nights prefer a moon-phase icon; days prefer sun unless rainy or snowy
    dl = desc.lower()
    if "thunderstorm" in dl or "storm" in dl:
        return "⛈️"
    if "snow" in dl or "sleet" in dl or "blizzard" in dl:
        return "❄️"
    if "rain" in dl or "drizzle" in dl or "shower" in dl:
        return "🌧️"
    if "fog" in dl or "mist" in dl or "haze" in dl:
        return "🌫️"
    if "cloud" in dl or "overcast" in dl:
        return "☁️"
    if "clear" in dl or "sun" in dl:
        return moon_icon(moon_phase) if night else "☀️"
    return moon_icon(moon_phase) if night else "🌡️"


night = is_night_time(local_dt)
icon = condition_icon(condition, night)
temp_text = temp_f.lstrip("+") + "°F"

if show_city:
    text = f"{location_display}: {icon} {temp_text}"
else:
    text = f"{icon} {temp_text}"

cache_write(text)
emit(text)
