-- Input, pointer, touchpad, and gestures

hl.config({
    cursor = {
        -- Software cursor avoids legacy DRM cursor-plane dropouts
        no_hardware_cursors = true,
        inactive_timeout = 0,
        hide_on_key_press = false,
        hide_on_touch = false,
        hide_on_tablet = false,
        invisible = false,
    },
})

hl.config({
    input = {
        follow_mouse = 1,
        sensitivity = 0.96,
        accel_profile = "flat",
        touchpad = {
            natural_scroll = true,

            -- Lua uses underscores for option names that were hyphenated in hyprlang
            tap_to_click = true,
        },
    },
})

-- Three-finger horizontal workspace swipe
hl.gesture({
    fingers = 3,
    direction = "horizontal",
    action = "workspace",
})

-- Example per-device input override
-- hl.device({ name = "epic-mouse-v1", sensitivity = -0.5 })
