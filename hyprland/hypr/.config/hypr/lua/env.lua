-- Environment exported to apps spawned by Hyprland

local env = {
    -- Cursor size for XCursor and Hyprcursor users
    XCURSOR_SIZE = "24",
    HYPRCURSOR_SIZE = "24",

    -- Session identity keeps portals and Electron apps on the right backend
    XDG_CURRENT_DESKTOP = "Hyprland",
    XDG_SESSION_DESKTOP = "Hyprland",
    XDG_SESSION_TYPE = "wayland",

    -- Qt theme integration is applied through qt6ct
    QT_QPA_PLATFORMTHEME = "qt6ct",
}

for name, value in pairs(env) do
    hl.env(name, value)
end
