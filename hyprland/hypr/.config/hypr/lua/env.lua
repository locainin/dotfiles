-- Environment exported to apps spawned by Hyprland

local env = {
    -- Cursor size for XCursor and Hyprcursor users
    XCURSOR_SIZE = "24",
    HYPRCURSOR_SIZE = "24",

    -- Session identity keeps portals and Electron/KDE apps on the right backend
    XDG_CURRENT_DESKTOP = "Hyprland",
    XDG_SESSION_DESKTOP = "Hyprland",
    KDE_FULL_SESSION = "true",
    KDE_SESSION_VERSION = "6",
    XDG_MENU_PREFIX = "plasma-",

    -- Qt theme integration is applied through qt6ct
    QT_QPA_PLATFORMTHEME = "qt6ct",
}

for name, value in pairs(env) do
    hl.env(name, value)
end

-- GPU forcing is intentionally left disabled
-- /dev/dri/by-path contains ':' and can be split as multiple DRM devices
-- hl.env("AQ_DRM_DEVICES", "/dev/dri/card0")
-- hl.env("WLR_DRM_DEVICES", "/dev/dri/card0")
-- hl.env("WLR_RENDERER", "vulkan")
-- hl.env("LIBVA_DRIVER_NAME", "iHD")
-- hl.env("__GLX_VENDOR_LIBRARY_NAME", "intel")
-- hl.env("GBM_BACKEND", "dri")
