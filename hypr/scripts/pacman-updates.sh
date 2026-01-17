#!/usr/bin/env bash
set -euo pipefail

# pacman updates count for Waybar (custom/updates module + drawer refresh signal 12)
# - normal call prints JSON for Waybar
# - --popup opens a scrollable list in the first available launcher/terminal

cache_dir="${XDG_CACHE_HOME:-$HOME/.cache}/hypr"
mkdir -p "$cache_dir"
state_file="$cache_dir/pacman-updates-last"
list_file="$cache_dir/pacman-updates-list"
lock_file="$cache_dir/pacman-updates.lock"
refresh_ttl=300
threshold=100
mode="json"

if [ "${1:-}" = "--popup" ]; then
  mode="popup"
fi

fetch_updates() {
  if command -v checkupdates >/dev/null 2>&1; then
    updates="$(checkupdates 2>/dev/null || true)"
  else
    updates="$(pacman -Qu --quiet 2>/dev/null || true)"
  fi

  count=0
  if [ -n "$updates" ]; then
    count="$(printf '%s\n' "$updates" | sed '/^\s*$/d' | wc -l | tr -d ' ')"
  fi

  printf '%s\n' "$updates" >"$list_file"
  printf '%s' "$count" >"$state_file" 2>/dev/null || true
}

ensure_updates() {
  if [ -f "$list_file" ]; then
    updates="$(cat "$list_file")"
    count="$(printf '%s\n' "$updates" | sed '/^\s*$/d' | wc -l | tr -d ' ')"
  else
    fetch_updates
  fi
}

load_cached_updates() {
  if [ -f "$list_file" ]; then
    updates="$(cat "$list_file")"
    count="$(printf '%s\n' "$updates" | sed '/^\s*$/d' | wc -l | tr -d ' ')"
    return 0
  fi
  return 1
}

queue_refresh() {
  (
    flock -n 9 || exit 0
    fetch_updates
    pkill -RTMIN+12 waybar 2>/dev/null || true
  ) 9>"$lock_file" &
}

show_popup() {
  ensure_updates

  if [ "$count" -eq 0 ]; then
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "Package Updates" "No updates available" -u low
    fi
    exit 0
  fi

  table_file="$(mktemp "$cache_dir/pacman-updates-table-XXXXXX")"
  ui_log="$cache_dir/pacman-updates-ui.log"

  printf '%s\n' "$updates" | awk '
    {
      pkg=$1; current=$2; new=$4;
      if (NF>=4) {
        printf("%s\t%s\t%s\n", pkg, current, new);
      }
    }' >"$table_file"

	  color_lookup() {
	    target="$1"
	    for file in "$HOME/.config/hypr/waybar/colors-wallust.css" "$HOME/.config/hypr/waybar/colors-base.css" "$HOME/.config/hypr/waybar/colors.css"; do
	      if [ -f "$file" ]; then
	        line="$(grep -i "@define-color[[:space:]]\\+${target}[[:space:]]\\+" "$file" | head -n1 || true)"
	        if [ -n "$line" ]; then
	          # prefer hex if present
	          match_hex="$(printf '%s\n' "$line" | sed -nE 's/.*(#[0-9a-fA-F]{6}).*/\1/p')"
	          if [ -n "$match_hex" ]; then
	            printf '%s' "$match_hex"
	            return 0
	          fi
	          # basic rgba() → hex converter, ignore alpha
	          # Allow optional whitespace after commas: rgba(10, 20, 30) and rgba(10,20,30) both match.
	          match_rgba="$(printf '%s\n' "$line" | sed -nE 's/.*rgba?\(([0-9]+)[[:space:]]*,[[:space:]]*([0-9]+)[[:space:]]*,[[:space:]]*([0-9]+).*/\1 \2 \3/p')"
	          if [ -n "$match_rgba" ]; then
	            IFS=' ' read -r r g b <<EOF
$match_rgba
EOF
	            printf '#%02x%02x%02x\n' "$r" "$g" "$b"
	            return 0
	          fi
	        fi
	      fi
	    done
	    return 1
	  }

  fg_hex="$(color_lookup fg || true)"
  bg_hex="$(color_lookup background || true)"
  accent_hex="$(color_lookup blue || true)"
  border_hex="$(color_lookup border || true)"
  badge_hex="$(color_lookup yellow || true)"
  accent_alt_hex="$(color_lookup magenta || true)"
  glow_hex="$(color_lookup cyan || true)"
  pill_hex="$(color_lookup pill || true)"
  stack_bg_hex="$(color_lookup stack-bg || true)"
  primary_hex="$(color_lookup primary || true)"
  secondary_hex="$(color_lookup secondary || true)"

  # fallbacks keep UI usable even if wallust colors are missing
  [ -z "$fg_hex" ] && fg_hex="#f0f0f0"
  [ -z "$bg_hex" ] && bg_hex="#111111"
  [ -z "$accent_hex" ] && accent_hex="#7aa2f7"
  [ -z "$border_hex" ] && border_hex="#2a2f41"
  [ -z "$badge_hex" ] && badge_hex="#e0af68"
  [ -z "$accent_alt_hex" ] && accent_alt_hex="#bb9af7"
  [ -z "$glow_hex" ] && glow_hex="#7dcfff"
  [ -z "$pill_hex" ] && pill_hex="$bg_hex"
  [ -z "$stack_bg_hex" ] && stack_bg_hex="$bg_hex"
  [ -z "$primary_hex" ] && primary_hex="$accent_hex"
  [ -z "$secondary_hex" ] && secondary_hex="$accent_alt_hex"

  if command -v python3 >/dev/null 2>&1; then
    unset _drawer_py_status
    python3 - <<'PY' "$table_file" "$count" "$fg_hex" "$bg_hex" "$accent_hex" "$border_hex" "$badge_hex" "$accent_alt_hex" "$glow_hex" "$pill_hex" "$stack_bg_hex" "$primary_hex" "$secondary_hex" "$ui_log" || _drawer_py_status=$?
import sys
from pathlib import Path
import traceback
from string import Template
try:
    import gi
    gi.require_version("Gtk", "3.0")
    from gi.repository import Gtk, Gdk, Pango
except Exception:
    sys.exit(1)

data_path = Path(sys.argv[1])
count = sys.argv[2]
fg, bg, accent, border, badge, accent_alt, glow, pill, stack_bg, primary, secondary = sys.argv[3:14]
log_path = Path(sys.argv[14])

def log(message: str) -> None:
    try:
        with log_path.open("a", encoding="utf-8") as handle:
            handle.write(message.rstrip() + "\n")
    except Exception:
        pass
rows = []
with data_path.open(encoding="utf-8") as handle:
    for line in handle:
        parts = line.rstrip("\n").split("\t")
        if len(parts) >= 3:
            rows.append(parts[:3])

if not rows:
    rows.append(("No updates", "-", "-"))

screen = Gdk.Screen.get_default()

def clamp(value):
    return max(0, min(255, int(round(value))))

def hex_to_rgb(value):
    value = value.strip().lstrip("#")
    if len(value) == 3:
        value = "".join([c * 2 for c in value])
    return tuple(int(value[i:i+2], 16) for i in (0, 2, 4))

def rgb_to_hex(rgb):
    return "#{:02x}{:02x}{:02x}".format(*(clamp(c) for c in rgb))

def blend(color_a, color_b, ratio):
    ar, ag, ab = hex_to_rgb(color_a)
    br, bgc, bb = hex_to_rgb(color_b)
    return rgb_to_hex((
        ar + (br - ar) * ratio,
        ag + (bgc - ag) * ratio,
        ab + (bb - ab) * ratio,
    ))

def tint(color, amount):
    return blend(color, "#ffffff", amount)

def shade(color, amount):
    return blend(color, "#000000", amount)

# derive a more obviously wallust-tinted palette, not just flat black
base_mix = blend(stack_bg, bg, 0.55)
panel_bg = blend(base_mix, pill, 0.55)
grad_top = blend(primary, glow, 0.35)
grad_bottom = shade(blend(border, accent, 0.40), 0.55)
accent_soft = tint(accent, 0.45)
accent_pill = tint(glow, 0.40)
row_even = blend(panel_bg, accent_alt, 0.22)
row_odd = blend(panel_bg, border, 0.18)
row_hover = tint(glow, 0.52)
row_divider = blend(border, glow, 0.35)
scroll_track = shade(base_mix, 0.25)
scroll_thumb = tint(accent, 0.65)
scroll_thumb_hover = tint(accent, 0.85)
badge_shadow = shade(badge, 0.65)
badge_plate = blend(badge, panel_bg, 0.35)
badge_caption = blend(fg, glow, 0.55)
badge_text = blend(fg, badge, 0.10)
badge_count = blend("#0a0a0a", badge, 0.15)
title_accent = blend(fg, accent, 0.45)

def to_rgba(color, alpha):
    r, g, b = hex_to_rgb(color)
    return f"rgba({r},{g},{b},{alpha})"

panel_bg_rgba = to_rgba(panel_bg, 0.88)
grad_top_rgba = to_rgba(grad_top, 0.82)
grad_bottom_rgba = to_rgba(grad_bottom, 0.96)
row_even_rgba = to_rgba(row_even, 0.85)
row_odd_rgba = to_rgba(row_odd, 0.82)
row_hover_rgba = to_rgba(row_hover, 0.92)
row_divider_rgba = to_rgba(row_divider, 0.42)
scroll_track_rgba = to_rgba(scroll_track, 0.55)
scroll_thumb_rgba = to_rgba(scroll_thumb, 0.85)
scroll_thumb_hover_rgba = to_rgba(scroll_thumb_hover, 0.95)
accent_soft_rgba = to_rgba(accent_soft, 0.85)
badge_shadow_rgba = to_rgba(badge_shadow, 0.70)
glow_rgba = to_rgba(glow, 0.32)
badge_plate_rgba = to_rgba(badge_plate, 0.94)
badge_caption_rgba = to_rgba(badge_caption, 0.75)
badge_text_rgba = to_rgba(badge_text, 0.92)
badge_count_rgba = to_rgba(badge_count, 0.98)
title_color_rgba = to_rgba(title_accent, 0.96)

css_template = Template(
    """
window.updates-window {
  background: linear-gradient(135deg, ${grad_top}, ${grad_bottom});
  color: ${fg};
  font-family: "JetBrainsMono Nerd Font", "FiraCode Nerd Font", monospace;
  transition: opacity 220ms ease-out;
}
.updates-root {
  padding: 32px 34px;
  border-radius: 26px;
  border: 1px solid ${border};
  background: ${panel_bg};
  box-shadow:
    0 32px 80px rgba(0,0,0,0.80),
    0 0 40px ${glow_rgba},
    0 0 0 1px rgba(255,255,255,0.06);
}
.updates-header {
  margin-bottom: 18px;
  padding-bottom: 8px;
  border-bottom: 1px solid ${row_divider_rgba};
}
.updates-title {
  font-size: 26px;
  font-weight: 900;
  letter-spacing: 0.08em;
  color: ${title_color_rgba};
}
.updates-badge-box {
  background: ${badge_plate_rgba};
  padding: 12px 24px;
  border-radius: 24px;
  border: 1px solid ${row_divider_rgba};
  color: ${badge_text_rgba};
  box-shadow:
    0 18px 40px rgba(0,0,0,0.65),
    0 0 24px ${badge_shadow_rgba};
}
.updates-badge-caption {
  font-size: 12px;
  letter-spacing: 0.35em;
  color: ${badge_caption_rgba};
}
.updates-badge-count {
  font-size: 34px;
  font-weight: 900;
  color: ${badge_count_rgba};
}
.updates-count {
  color: rgba(255,255,255,0.78);
  font-size: 15px;
}
treeview.updates-tree {
  background: transparent;
  color: ${fg};
  font-size: 20px;
  font-weight: 500;
  transition: background 220ms ease, color 220ms ease;
}
treeview.updates-tree {
  border: none;
}
treeview.updates-tree row {
  min-height: 40px;
  transition: background 200ms ease, color 200ms ease;
  border-radius: 12px;
  box-shadow: inset 0 -1px 0 ${row_divider_rgba};
}
treeview.updates-tree row:nth-child(even) {
  background: ${row_even_rgba};
}
treeview.updates-tree row:nth-child(odd) {
  background: ${row_odd_rgba};
}
treeview.updates-tree row:selected,
treeview.updates-tree row:selected:hover {
  background: ${row_hover_rgba};
  color: #050505;
  font-weight: 800;
}
treeview.updates-tree row:hover {
  background: ${row_hover_rgba};
  color: #050505;
}
scrolledwindow.updates-scroll {
  border-radius: 18px;
  padding-right: 6px;
  border: none;
  background: ${scroll_track_rgba};
}
scrolledwindow.updates-scroll scrollbar slider {
  background: ${scroll_thumb_rgba};
  border-radius: 999px;
  min-width: 6px;
  min-height: 6px;
  transition: background 180ms ease;
}
scrolledwindow.updates-scroll scrollbar slider:hover {
  background: ${scroll_thumb_hover_rgba};
}
treeview.updates-tree header {
  background: ${accent_pill};
  color: ${accent_soft_rgba};
  font-weight: 800;
  letter-spacing: 0.10em;
  font-size: 16px;
  box-shadow: 0 1px 0 ${row_divider_rgba};
}
"""
)

css = css_template.substitute(
    grad_top=grad_top_rgba,
    grad_bottom=grad_bottom_rgba,
    fg=fg,
    border=border,
    panel_bg=panel_bg_rgba,
    row_divider_rgba=row_divider_rgba,
    badge_shadow_rgba=badge_shadow_rgba,
    row_even_rgba=row_even_rgba,
    row_odd_rgba=row_odd_rgba,
    row_hover_rgba=row_hover_rgba,
    scroll_track_rgba=scroll_track_rgba,
    scroll_thumb_rgba=scroll_thumb_rgba,
    scroll_thumb_hover_rgba=scroll_thumb_hover_rgba,
    accent_pill=accent_pill,
    accent_soft_rgba=accent_soft_rgba,
    glow_rgba=glow_rgba,
    badge_plate_rgba=badge_plate_rgba,
    badge_caption_rgba=badge_caption_rgba,
    badge_text_rgba=badge_text_rgba,
    badge_count_rgba=badge_count_rgba,
    title_color_rgba=title_color_rgba,
)
provider = Gtk.CssProvider()
provider.load_from_data(css.encode("utf-8"))
if screen is not None:
    Gtk.StyleContext.add_provider_for_screen(
        screen, provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
    )

class UpdatesWindow(Gtk.Window):
    def __init__(self):
        super().__init__(title=f"Pacman updates ({count})")
        self.set_default_size(960, 720)
        self.set_position(Gtk.WindowPosition.CENTER)
        self.get_style_context().add_class("updates-window")
        self.connect("destroy", Gtk.main_quit)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        root.get_style_context().add_class("updates-root")
        self.add(root)

        header = Gtk.Box(spacing=12)
        header.get_style_context().add_class("updates-header")
        title = Gtk.Label(label="Pacman updates")
        title.set_xalign(0.0)
        title.get_style_context().add_class("updates-title")
        badge_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=4)
        badge_box.get_style_context().add_class("updates-badge-box")
        badge_box.set_halign(Gtk.Align.END)
        badge_caption = Gtk.Label(label="TOTAL UPDATES")
        badge_caption.set_xalign(1.0)
        badge_caption.get_style_context().add_class("updates-badge-caption")
        badge_count = Gtk.Label(label=count)
        badge_count.set_xalign(1.0)
        badge_count.get_style_context().add_class("updates-badge-count")
        badge_box.pack_start(badge_caption, False, False, 0)
        badge_box.pack_start(badge_count, False, False, 0)
        header.pack_start(title, True, True, 0)
        header.pack_end(badge_box, False, False, 0)
        root.pack_start(header, False, False, 0)

        subtitle = Gtk.Label(label="Live package diff")
        subtitle.set_xalign(0.0)
        subtitle.get_style_context().add_class("updates-count")
        root.pack_start(subtitle, False, False, 0)

        store = Gtk.ListStore(str, str, str)
        for pkg, cur, new in rows:
            store.append([pkg, cur, new])

        tree = Gtk.TreeView(model=store)
        tree.get_style_context().add_class("updates-tree")
        tree.set_headers_visible(True)
        tree.set_grid_lines(Gtk.TreeViewGridLines.NONE)
        tree.set_enable_search(True)
        tree.set_search_column(0)
        tree.set_hover_selection(True)
        tree.set_activate_on_single_click(False)
        tree.get_selection().set_mode(Gtk.SelectionMode.NONE)

        renderer_pkg = Gtk.CellRendererText()
        renderer_pkg.set_property("weight", 800)
        renderer_pkg.set_property("ellipsize", Pango.EllipsizeMode.END)
        col_pkg = Gtk.TreeViewColumn("Package", renderer_pkg, text=0)
        col_pkg.set_expand(True)
        tree.append_column(col_pkg)

        renderer_cur = Gtk.CellRendererText()
        renderer_cur.set_property("foreground", "#cfcfcf")
        renderer_cur.set_property("ellipsize", Pango.EllipsizeMode.END)
        renderer_cur.set_property("xalign", 1.0)
        col_cur = Gtk.TreeViewColumn("Current", renderer_cur, text=1)
        col_cur.set_alignment(1.0)
        col_cur.set_min_width(130)
        tree.append_column(col_cur)

        renderer_new = Gtk.CellRendererText()
        renderer_new.set_property("foreground", accent)
        renderer_new.set_property("weight", 800)
        renderer_new.set_property("ellipsize", Pango.EllipsizeMode.END)
        renderer_new.set_property("xalign", 1.0)
        col_new = Gtk.TreeViewColumn("New", renderer_new, text=2)
        col_new.set_alignment(1.0)
        col_new.set_min_width(130)
        tree.append_column(col_new)

        scrolled = Gtk.ScrolledWindow()
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_overlay_scrolling(False)
        scrolled.set_margin_start(2)
        scrolled.set_margin_end(2)
        scrolled.set_margin_top(2)
        scrolled.set_margin_bottom(2)
        scrolled.get_style_context().add_class("updates-scroll")
        scrolled.add(tree)
        root.pack_start(scrolled, True, True, 0)

        self.show_all()

log(f"GTK UI: starting window with {len(rows)} rows")
try:
    UpdatesWindow()
    Gtk.main()
    log("GTK UI: closed cleanly")
    sys.exit(0)
except Exception as exc:
    log("GTK UI ERROR: " + repr(exc))
    log(traceback.format_exc())
    sys.exit(1)
PY
    status=${_drawer_py_status:-0}
    if [ "$status" -eq 0 ]; then
      rm -f "$table_file"
      exit 0
    fi
  fi
  echo "pacman-updates: GTK UI failed, see $ui_log" >&2
  rm -f "$table_file"
  exit 1
}

if [ "$mode" = "popup" ]; then
  show_popup
fi

# cached path (Waybar poll) should re-use last list immediately; we still need the
# previous count for threshold notifications when we do a full refresh
prev_count=0
if [ -f "$state_file" ]; then
  prev_count="$(cat "$state_file" 2>/dev/null || echo 0)"
fi

used_cache=0
if load_cached_updates; then
  used_cache=1
else
  fetch_updates
fi

if [ "$used_cache" -eq 1 ]; then
  now_epoch=$(date +%s)
  last_refresh=0
  if [ -f "$state_file" ]; then
    last_refresh="$(stat -c %Y "$state_file" 2>/dev/null || echo 0)"
  fi
  age=$((now_epoch - last_refresh))
  if [ "$last_refresh" -eq 0 ] || [ "$age" -ge "$refresh_ttl" ]; then
    queue_refresh
  fi
fi

if [ "$count" -gt 0 ]; then
  text=" $count"
  preview_lines=20
  escaped_list="$(printf '%s\n' "$updates" | head -n "$preview_lines" | sed 's/\\\\/\\\\\\\\/g; s/\"/\\\"/g; s/$/\\n/' | tr -d '\n')"
  more_note=""
  if [ "$count" -gt "$preview_lines" ]; then
    more_note="…\\nClick to view full list"
  else
    more_note="\\nClick to view full list"
  fi
  tooltip="$(printf 'Updates (%s):\\n%s%s' "$count" "$escaped_list" "$more_note")"
  class="updates available"
else
  text=" 0"
  tooltip="No updates"
  class="updates none"
fi

if [ "$used_cache" -eq 0 ]; then
  if [ "$count" -gt "$threshold" ] && [ "$prev_count" -le "$threshold" ]; then
    if command -v notify-send >/dev/null 2>&1; then
      notify-send "Package Updates" "$count packages available" -u normal
    fi
  fi
fi

printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$text" "$tooltip" "$class"
