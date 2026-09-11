-- Neutrino - Hyprland
-- ~/.config/hypr/hyprland.lua
--
-- Lua config. Hyprland loads this in preference to hyprland.conf, which is
-- deprecated -- and several options in the old file no longer exist at all:
-- gestures:workspace_swipe, gestures:workspace_swipe_fingers,
-- dwindle:pseudotile and misc:vfr, plus `togglesplit`, which is a layout
-- message here rather than a dispatcher.
--
-- grayscale ramp, shared with every other config in this repo:
--   #0b0b0b base   #121212 bar    #1a1a1a surface  #242424 overlay
--   #303030 border #4d4d4d muted  #7a7a7a subtext  #c2c2c2 text
--   #ebebeb bright

------------------
---- PROGRAMS ----
------------------

-- Binary names, not .desktop names. Verify on the real system:
--   which alacritty thunar codium zen-browser floorp wofi
local terminal    = "alacritty"
local fileManager = "thunar"
local editor      = "codium"
local zen         = "zen-browser"
local floorp      = "floorp"
-- pkill first, so a second press dismisses the launcher instead of stacking
-- another instance behind it
local menu        = "pkill wofi || wofi --show drun"

------------------
---- MONITORS ----
------------------

-- Empty output matches every display, which is what you want on a laptop that
-- gets docked. `hyprctl monitors` for real names when you need a per-display
-- rule.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = "auto",
})

-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_SESSION_DESKTOP", "Hyprland")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "qt6ct")
hl.env("QT_WAYLAND_DISABLE_WINDOWDECORATION", "1")
hl.env("GDK_BACKEND", "wayland,x11")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("XCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("HYPRCURSOR_SIZE", "24")

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    hl.exec_cmd("/usr/lib/polkit-kde-authentication-agent-1")
    hl.exec_cmd("quickshell")
    -- env alone does not retheme the cursor Hyprland draws over the desktop
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")
end)

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in     = 5,
        gaps_out    = 10,
        border_size = 2,

        col = {
            active_border   = "rgba(ebebebcc)",
            inactive_border = "rgba(303030aa)",
        },

        resize_on_border = true,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding         = 6,
        rounding_power   = 2,
        active_opacity   = 1.0,
        inactive_opacity = 0.96,

        shadow = {
            enabled      = true,
            range        = 18,
            render_power = 3,
            -- 0xAARRGGBB, so this is black at 40 percent
            color        = 0x66000000,
        },

        blur = {
            enabled    = true,
            size       = 6,
            passes     = 2,
            noise      = 0.015,
            contrast   = 0.9,
            brightness = 0.7,
        },
    },

    animations = {
        enabled = true,
    },

    dwindle = {
        preserve_split = true,
    },

    misc = {
        force_default_wallpaper = 0,
        disable_hyprland_logo   = true,
    },
})

hl.curve("neutrino", { type = "bezier", points = { {0.22, 1}, {0.36, 1} } })

hl.animation({ leaf = "global",     enabled = true, speed = 6, bezier = "neutrino" })
hl.animation({ leaf = "border",     enabled = true, speed = 6, bezier = "neutrino" })
hl.animation({ leaf = "windows",    enabled = true, speed = 4, bezier = "neutrino", style = "popin 92%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 3, bezier = "neutrino", style = "popin 92%" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3, bezier = "neutrino" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 4, bezier = "neutrino", style = "slidefade 12%" })

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout    = "us",
        follow_mouse = 1,
        sensitivity  = 0,

        touchpad = {
            natural_scroll       = true,
            disable_while_typing = true,
            scroll_factor        = 0.6,
            -- spelled with dashes, which is not a bare Lua identifier
            ["tap-to-click"]     = true,
        },
    },
})

-- Replaces gestures:workspace_swipe, which no longer exists.
hl.gesture({
    fingers   = 3,
    direction = "horizontal",
    action    = "workspace",
})

---------------------
---- KEYBINDINGS ----
---------------------

local mod = "SUPER"

-- launchers
hl.bind("CTRL + SPACE",      hl.dsp.exec_cmd(menu))
hl.bind(mod .. " + Return",  hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + A",       hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + E",       hl.dsp.exec_cmd(fileManager))
hl.bind(mod .. " + V",       hl.dsp.exec_cmd(editor))
hl.bind(mod .. " + Z",       hl.dsp.exec_cmd(zen))
hl.bind(mod .. " + F",       hl.dsp.exec_cmd(floorp))

-- window management
-- fullscreen and float sit on SHIFT, since plain F and V launch apps
hl.bind(mod .. " + Q",         hl.dsp.window.close())
hl.bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen())
hl.bind(mod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())
hl.bind(mod .. " + P",         hl.dsp.window.pseudo())
hl.bind(mod .. " + J",         hl.dsp.layout("togglesplit"))

-- focus
hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- workspaces
for i = 1, 5 do
    hl.bind(mod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- mouse
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- screenshot
hl.bind("Print", hl.dsp.exec_cmd([[grim -g "$(slurp)" - | wl-copy]]))

-- laptop function keys
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

----------------------
---- WINDOW RULES ----
----------------------

hl.window_rule({
    name  = "suppress-maximize-events",
    match = { class = ".*" },
    suppress_event = "maximize",
})

hl.window_rule({
    -- Fixes dragging issues with XWayland
    name  = "fix-xwayland-drags",
    match = {
        class      = "^$",
        title      = "^$",
        xwayland   = true,
        float      = true,
        fullscreen = false,
        pin        = false,
    },
    no_focus = true,
})

hl.window_rule({
    name  = "float-pavucontrol",
    match = { class = "^(pavucontrol)$" },
    float = true,
})

hl.window_rule({
    name  = "float-nwg-look",
    match = { class = "^(nwg-look)$" },
    float = true,
})
