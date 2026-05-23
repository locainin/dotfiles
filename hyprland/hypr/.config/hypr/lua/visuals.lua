-- Look, layout, animation, and compositor behavior

hl.config({
    general = {
        gaps_in = 8,
        gaps_out = 18,
        border_size = 2,

        -- Gradient mirrors the previous active border exactly
        col = {
            active_border = { colors = { "rgba(7aa2f7ff)", "rgba(bb9af7ff)" }, angle = 45 },
            inactive_border = "rgba(2a2f41cc)",
        },

        resize_on_border = false,
        allow_tearing = false,
        layout = "dwindle",
    },
})

hl.config({
    decoration = {
        rounding = 10,
        rounding_power = 2,

        -- Keep existing translucent focused and inactive windows
        active_opacity = 0.97,
        inactive_opacity = 0.92,

        shadow = {
            enabled = true,
            range = 3,
            render_power = 2,
            color = "rgba(1a1a1aee)",
        },

        blur = {
            enabled = true,
            size = 5,
            passes = 3,
            vibrancy = 0.17,
        },
    },
})

hl.config({
    render = {
        -- Keep KMS color/HDR commits out of the failing Intel panel path
        cm_enabled = false,
        cm_auto_hdr = 0,
        send_content_type = false,
        icc_vcgt_enabled = false,
        -- Avoid stale Quickshell layer buffers appearing only in screenshots
        keep_unmodified_copy = false,
    },
})

hl.config({
    animations = {
        enabled = true,
    },
})

-- Curves match the old hyprlang animation block
hl.curve("easeOutQuint", { type = "bezier", points = { { 0.23, 1 }, { 0.32, 1 } } })
hl.curve("easeInOutCubic", { type = "bezier", points = { { 0.65, 0.05 }, { 0.36, 1 } } })
hl.curve("linear", { type = "bezier", points = { { 0, 0 }, { 1, 1 } } })
hl.curve("quick", { type = "bezier", points = { { 0.15, 0 }, { 0.1, 1 } } })

hl.animation({ leaf = "global", enabled = true, speed = 10, bezier = "default" })
hl.animation({ leaf = "border", enabled = true, speed = 5.3, bezier = "easeOutQuint" })
hl.animation({ leaf = "windows", enabled = true, speed = 4.8, bezier = "easeOutQuint" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.1, bezier = "easeOutQuint", style = "popin 87%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 1.6, bezier = "linear", style = "popin 87%" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 1.7, bezier = "quick" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 1.5, bezier = "quick" })
hl.animation({ leaf = "layers", enabled = true, speed = 3.6, bezier = "easeOutQuint", style = "slide top" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 3.9, bezier = "easeOutQuint", style = "slide top" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 1.5, bezier = "linear", style = "slide top" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 1.9, bezier = "easeInOutCubic", style = "slide" })
hl.animation({ leaf = "zoomFactor", enabled = true, speed = 7.0, bezier = "quick" })

hl.config({
    dwindle = {
        -- Dynamic splits preserve the previous Windows-like close behavior
        preserve_split = false,
    },
})

hl.config({
    master = {
        new_status = "master",
    },
})

hl.config({
    misc = {
        force_default_wallpaper = -1,
        disable_hyprland_logo = true,
        background_color = "rgba(000000ff)",

        -- Keep media rendering on hidden workspaces without stalling video
        render_unfocused_fps = 60,

        -- Recover desktop if a lock surface exits unexpectedly
        allow_session_lock_restore = true,
    },
})

hl.config({
    xwayland = {
        force_zero_scaling = true,
    },
})
