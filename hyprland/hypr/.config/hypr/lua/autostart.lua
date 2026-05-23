-- One-shot session startup

local exec_once_commands = {
    -- Export compositor env before tray and portal clients race startup
    "dbus-update-activation-environment --systemd --all",
    "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP DISPLAY XDG_RUNTIME_DIR PATH QT_QPA_PLATFORMTHEME GBM_BACKEND LIBVA_DRIVER_NAME __GLX_VENDOR_LIBRARY_NAME __EGL_VENDOR_LIBRARY_FILENAMES",
    "sh -lc 'systemctl --user --no-block restart xdg-desktop-portal.service xdg-desktop-portal-hyprland.service'",

    -- Bridge Wayland capture sources for XWayland clients
    "sh -lc 'command -v xwaylandvideobridge >/dev/null || exit 0; pgrep -f xwaylandvideobridge >/dev/null || setsid -f xwaylandvideobridge >/dev/null 2>&1'",

    -- Restore Bluetooth and start the primary shell surface
    "~/.config/hypr/scripts/bluetooth-restore.sh",
    "~/.config/hypr/scripts/start-shell.sh",

    -- Close Vicinae on focus loss because it is a layer surface
    "sh -lc 'pgrep -f \"$HOME/.config/hypr/scripts/vicinae-focus-watcher.py\" >/dev/null || setsid -f \"$HOME/.config/hypr/scripts/vicinae-focus-watcher.py\" >/dev/null 2>&1'",

    -- Keep clipboard data after the source app exits
    "wl-paste --type text --watch cliphist store",
    "wl-paste --type image --watch cliphist store",
    "wl-paste --type text --watch $HOME/.config/hypr/scripts/clipboard-persist.sh text/plain",
    "wl-paste --type image/png --watch $HOME/.config/hypr/scripts/clipboard-persist.sh image/png",

    -- Wallpaper restore and health check mirror the old main config
    "$HOME/.config/hypr/scripts/wallpaper-ensure.sh",
    "$HOME/.config/hypr/scripts/session-healthcheck.sh",

    -- UnixNotis session bootstrap
    "dbus-update-activation-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP DISPLAY XDG_RUNTIME_DIR PATH",
    "systemctl --user import-environment WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE XDG_SESSION_DESKTOP DISPLAY XDG_RUNTIME_DIR PATH",
    "systemctl --user --no-block restart unixnotis-daemon.service",
}

hl.on("hyprland.start", function()
    for _, command in ipairs(exec_once_commands) do
        hl.exec_cmd(command)
    end
end)
