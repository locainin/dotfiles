#!/usr/bin/env python3
"""
Weather helper for the Hypr Waybar configuration.
Defaults for location, city label, and unit system live here as a single edit point.
Hypr env vars (WAYBAR_WEATHER_LOCATION / WAYBAR_WEATHER_SHOW_CITY / WAYBAR_WEATHER_UNITS)
override these defaults when needed.
The script prints a tiny JSON object for the Waybar custom/weather module.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from datetime import datetime
from typing import Literal

# ----------------------------
# defaults intended for local override
# ----------------------------
DEFAULT_LOCATION = ""  # set once to avoid relying on env vars
DEFAULT_SHOW_CITY = False      # False avoids showing a location label in the bar by default
DEFAULT_UNITS: Literal["imperial", "metric"] = "imperial"  # imperial=°F, metric=°C
# ----------------------------

ENV_LOCATION = "WAYBAR_WEATHER_LOCATION"
ENV_SHOW_CITY = "WAYBAR_WEATHER_SHOW_CITY"
ENV_UNITS = "WAYBAR_WEATHER_UNITS"


@dataclass(frozen=True)
class Settings:
    # wraps the resolved location, city toggle, and unit system so downstream code stays tidy
    location: str
    show_city: bool
    units: Literal["imperial", "metric"]


@dataclass(frozen=True)
class WeatherReading:
    # holds the parsed values we actually render in Waybar (emoji + temp + optional label)
    temp_text: str
    condition: str
    is_night: bool
    moon_phase: str
    location_label: str


def error_exit(message: str) -> None:
    # print a failure message so Waybar shows the outage instead of stale data
    safe = message.replace("\\", "\\\\").replace('"', '\\"')
    sys.stdout.write(f'{{"text":"{safe}"}}\n')
    sys.exit(0)


def load_settings() -> Settings:
    # pull defaults plus env overrides into one Settings object
    env_loc = os.environ.get(ENV_LOCATION, "").strip()
    # prefer user-provided env location, otherwise fall back to the default above
    location = env_loc if env_loc else DEFAULT_LOCATION.strip()
    if not location or location.lower() == "city, state":
        error_exit("Set WAYBAR_WEATHER_LOCATION for weather")

    env_city = os.environ.get(ENV_SHOW_CITY, "").strip().lower()
    if env_city in {"1", "true", "yes"}:
        show_city = True
    elif env_city in {"0", "false", "no"}:
        show_city = False
    else:
        show_city = bool(DEFAULT_SHOW_CITY)

    env_units = os.environ.get(ENV_UNITS, "").strip().lower()
    # respect explicit unit request; otherwise use the default for the entire script
    if env_units in {"metric", "c", "celsius"}:
        units = "metric"
    elif env_units in {"imperial", "f", "fahrenheit"}:
        units = "imperial"
    else:
        units = DEFAULT_UNITS

    return Settings(location=location, show_city=show_city, units=units)


def fetch_weather_json(location: str) -> dict:
    # call wttr.in JSON API for the resolved location and fail fast on errors
    encoded = urllib.parse.quote_plus(location, safe=",")
    url = f"https://wttr.in/{encoded}?format=j1"
    try:
        with urllib.request.urlopen(url, timeout=8) as resp:
            payload = resp.read().decode("utf-8", errors="replace")
    except (urllib.error.URLError, TimeoutError, OSError) as exc:
        error_exit(f"Weather: provider down ({exc.__class__.__name__})")

    try:
        return json.loads(payload)  # the response is tiny, so reading it fully is fine
    except json.JSONDecodeError:
        error_exit("Weather: provider returned malformed JSON")
    return {}


def parse_reading(data: dict, settings: Settings) -> WeatherReading:
    # squeeze the JSON response down into only the fields we need for the widget
    current = (data.get("current_condition") or [{}])[0]  # now/observed values
    weather = (data.get("weather") or [{}])[0]            # day-level metadata
    astronomy = (weather.get("astronomy") or [{}])[0]     # sunrise/sunset/moon info

    if settings.units == "metric":
        temp_raw = str(current.get("temp_C", "")).strip()
        unit_suffix = "°C"
    else:
        temp_raw = str(current.get("temp_F", "")).strip()
        unit_suffix = "°F"

    if not temp_raw:
        error_exit("Weather: missing temperature")

    # format temperature for display; drop leading '+' but retain '-' for negative temps
    temp_text = temp_raw.lstrip("+") + unit_suffix
    condition = str((current.get("weatherDesc") or [{}])[0].get("value", "")).strip()
    local_dt = str(current.get("localObsDateTime", "")).strip()
    moon_phase = str(astronomy.get("moon_phase", "")).strip()
    is_night = determine_night(local_dt)

    return WeatherReading(
        temp_text=temp_text,
        condition=condition,
        is_night=is_night,
        moon_phase=moon_phase,
        location_label=settings.location,
    )


def determine_night(local_str: str) -> bool:
    # treat the location's local time between 20:00-06:59 as night so we can use moon icons
    try:
        dt = datetime.strptime(local_str, "%Y-%m-%d %I:%M %p")
    except ValueError:
        return False
    return dt.hour >= 20 or dt.hour < 7


def moon_icon(moon_phase: str) -> str:
    # map textual moon phase to the closest Unicode moon glyph
    phase_lower = moon_phase.lower()
    if "new" in phase_lower:
        return "🌑"
    if "waxing crescent" in phase_lower:
        return "🌒"
    if "first quarter" in phase_lower:
        return "🌓"
    if "waxing gibbous" in phase_lower:
        return "🌔"
    if "full" in phase_lower:
        return "🌕"
    if "waning gibbous" in phase_lower:
        return "🌖"
    if "last quarter" in phase_lower or "third quarter" in phase_lower:
        return "🌗"
    if "waning crescent" in phase_lower:
        return "🌘"
    return "🌙"


def condition_icon(description: str, is_night: bool, moon_phase: str) -> str:
    # map the text condition (rain, snow, clear, etc.) to one emoji
    dl = description.lower()
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
        return moon_icon(moon_phase) if is_night else "☀️"
    return moon_icon(moon_phase) if is_night else "🌡️"


def format_output(settings: Settings, reading: WeatherReading) -> str:
    # build the final Waybar text string with or without the city label
    icon = condition_icon(reading.condition, reading.is_night, reading.moon_phase)
    if settings.show_city:
        # default path: prefix with the location label so different bars can reuse the script easily
        return f"{reading.location_label}: {icon} {reading.temp_text}"
    return f"{icon} {reading.temp_text}"


def main() -> None:
    # load settings, fetch data, format, and print the JSON payload
    settings = load_settings()
    # the fetch/parse steps intentionally exit with informative errors instead of caching
    data = fetch_weather_json(settings.location)
    reading = parse_reading(data, settings)
    text = format_output(settings, reading)
    safe = text.replace("\\", "\\\\").replace('"', '\\"')
    sys.stdout.write(f'{{"text":"{safe}"}}\n')


if __name__ == "__main__":
    main()
