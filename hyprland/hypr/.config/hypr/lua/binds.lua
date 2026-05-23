-- Global keybinds and media keys

local programs = require("lua.programs")
local main_mod = "SUPER"

-- Launcher release binds keep Super tap behavior predictable
hl.bind("SUPER + Super_L", hl.dsp.exec_cmd("~/.config/hypr/scripts/vicinae-toggle.sh"), { release = true })
hl.bind("SUPER + Super_R", hl.dsp.exec_cmd("~/.config/hypr/scripts/vicinae-toggle.sh"), { release = true })

-- Session and app launchers
hl.bind(main_mod .. " + C", hl.dsp.window.close())
hl.bind(main_mod .. " + F", hl.dsp.exec_cmd("brave-origin-nightly --proxy-server=socks5://10.64.0.1 --force-webrtc-ip-handling-policy --webrtc-ip-handling-policy=disable_non_proxied_udp"))
hl.bind(main_mod .. " + T", hl.dsp.exec_cmd(programs.terminal))
hl.bind(main_mod .. " + RETURN", hl.dsp.exec_cmd(programs.terminal))
hl.bind(main_mod .. " + B", hl.dsp.exec_cmd("gtk-launch bitwarden.desktop"))
hl.bind(main_mod .. " + V", hl.dsp.exec_cmd("$HOME/.config/hypr/scripts/clipboard-history.sh"))

-- Fullscreen helper mirrors dwindle splits without app-level UI toggles
hl.bind(main_mod .. " + P", hl.dsp.exec_cmd("~/.config/hypr/scripts/fullscreen-toggle.py"))

-- Reload paths
hl.bind("CTRL + SHIFT + R", hl.dsp.exec_cmd("sh -lc '~/.config/hypr/scripts/reload-all.sh'"))
hl.bind(main_mod .. " + SHIFT + R", hl.dsp.exec_cmd("$HOME/.local/bin/selector.sh"))

-- Directional focus
hl.bind("ALT + left", hl.dsp.focus({ direction = "left" }))
hl.bind("ALT + right", hl.dsp.focus({ direction = "right" }))
hl.bind("ALT + up", hl.dsp.focus({ direction = "up" }))
hl.bind("ALT + down", hl.dsp.focus({ direction = "down" }))

-- Workspace cycling stays delegated to the existing script
hl.bind("CTRL + left", hl.dsp.exec_cmd("~/.config/hypr/scripts/workspace-cycle.sh prev"))
hl.bind("CTRL + right", hl.dsp.exec_cmd("~/.config/hypr/scripts/workspace-cycle.sh next"))

-- Block browser new-window shortcuts
hl.bind("CTRL + M", hl.dsp.exec_cmd("true"))
hl.bind("CTRL + N", hl.dsp.exec_cmd("true"))

-- Fixed workspace IDs match lua.monitors and panel expectations
for workspace = 1, 5 do
    hl.bind(main_mod .. " + " .. workspace, hl.dsp.focus({ workspace = workspace }))
    hl.bind(main_mod .. " + F" .. workspace, hl.dsp.focus({ workspace = workspace }))
end

-- Mouse interactions
hl.bind("ALT + mouse:272", hl.dsp.window.drag(), { mouse = true })
hl.bind("ALT + mouse:273", hl.dsp.window.resize(), { mouse = true })
hl.bind("mouse:274", hl.dsp.window.drag(), { mouse = true })

-- Media keys call existing scripts so panels and notifications stay aligned
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("env ENABLE_VOLUME_SOUND=1 ENABLE_VOLUME_OSD=0 $HOME/.config/hypr/scripts/volume-osd.sh up"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("env ENABLE_VOLUME_SOUND=1 ENABLE_VOLUME_OSD=0 $HOME/.config/hypr/scripts/volume-osd.sh down"), { locked = true, repeating = true })
hl.bind("XF86AudioMute", hl.dsp.exec_cmd("env ENABLE_VOLUME_SOUND=1 ENABLE_VOLUME_OSD=0 $HOME/.config/hypr/scripts/volume-osd.sh toggle"), { locked = true, repeating = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp", hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness-step.sh up 5"), { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("~/.config/hypr/scripts/brightness-step.sh down 5"), { locked = true, repeating = true })

-- Player controls
hl.bind("XF86AudioNext", hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev", hl.dsp.exec_cmd("playerctl previous"), { locked = true })

-- Screenshot, minimize, restore, and wallpaper helpers
hl.bind("SUPER + SHIFT + S", hl.dsp.exec_cmd("bash -lc 'qs=\"$HOME/.config/quickshell/dynamic_island/scripts/screenshot.sh\"; if [ -x \"$qs\" ]; then exec \"$qs\"; fi; exec \"$HOME/.config/hypr/scripts/screenshot.sh\"'"), { locked = true })
hl.bind("SUPER + M", hl.dsp.exec_cmd("~/.config/hypr/minhypr/minimize-window.py"))
hl.bind("SUPER + N", hl.dsp.exec_cmd("~/.config/hypr/minhypr/launch-menu.sh"))
hl.bind("SUPER + W", hl.dsp.exec_cmd("~/.config/hypr/scripts/wallpaper-cycle.sh next"))

-- Special workspace is intentionally disabled to preserve the previous warning
-- hl.bind(main_mod .. " + S", hl.dsp.workspace.toggle_special("magic"))
-- hl.bind(main_mod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))
