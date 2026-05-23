-- Window and layer rules
-- Rule order matches the old hyprlang files

hl.window_rule({
    name = "prefer-active-workspace",
    match = { class = "negative:^$" },
    workspace = "unset",
})

hl.window_rule({
    name = "xwayland-drag-helper",
    match = {
        class = "^$",
        title = "^$",
        xwayland = true,
        float = true,
        fullscreen = false,
        pin = false,
    },
    no_focus = true,
})

hl.window_rule({
    name = "xwayland-video-bridge-fixes",
    match = { class = "^(xwaylandvideobridge)$" },
    float = true,
    decorate = false,
    no_shadow = true,
    no_initial_focus = true,
    no_focus = true,
    no_anim = true,
    no_blur = true,
    max_size = { 1, 1 },
    opacity = "0.0",
})

hl.window_rule({
    name = "rofi",
    match = { class = "^(rofi)$" },
    float = true,
    center = true,
})

hl.window_rule({
    name = "recorder-picker",
    match = { initial_class = "^(recorder-picker)$" },
    float = true,
    size = "500 250",
    center = true,
    stay_focused = true,
})

hl.window_rule({
    name = "smplayer-render-unfocused",
    match = {
        class = "^(smplayer)$",
        xwayland = true,
    },
    render_unfocused = true,
})

hl.layer_rule({
    name = "vicinae-layer",
    match = { namespace = "^(vicinae)$" },
    blur = true,
})

hl.window_rule({
    name = "suppress-maximize-events",
    match = { class = "negative:^$" },
    suppress_event = "maximize",
})

-- Flameshot rules stay disabled while grim and satty handle screenshots
-- hl.window_rule({ name = "flameshot", match = { class = "^(flameshot)$" }, float = true, stay_focused = true })
