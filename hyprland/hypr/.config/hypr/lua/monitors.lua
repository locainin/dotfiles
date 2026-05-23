-- Monitor and workspace defaults

-- Fallback monitor rule keeps random connectors usable at login
hl.monitor({
    output = "",
    mode = "preferred",
    position = "auto",
    scale = 1,
})

-- Persistent workspaces keep panels showing the expected fixed IDs
for workspace = 1, 5 do
    hl.workspace_rule({
        workspace = tostring(workspace),
        persistent = true,
    })
end

-- Examples kept close to the old config for quick local changes
-- hl.monitor({ output = "DP-1", mode = "2560x1440@144", position = "auto", scale = 1 })
-- hl.monitor({ output = "HDMI-A-1", mode = "1920x1080@60", position = "auto", scale = 1 })
-- hl.monitor({ output = "DP-1", mode = "preferred", position = "auto", scale = 1, mirror = "HDMI-A-1" })
