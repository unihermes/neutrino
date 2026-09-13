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

-- Binary names, not .desktop names.
local terminal    = "alacritty"
local fileManager = "thunar"
local editor      = "codium"
local zen         = "zen-browser"
local floorp      = "floorp"
-- pkill first, so a second press dismisses the launcher instead of stacking
-- another instance behind it. The stylesheet is Quickshell's copy with the bar's
-- corner radius applied (AppearanceSync.qml), falling back to the repo's own
-- until the shell has written one.
local menu        = "pkill wofi || { s=~/.local/state/neutrino/wofi.css; [ -r \"$s\" ] || s=~/.config/wofi/style.css; wofi --show drun --style \"$s\"; }"

-- Animation Speed from the bar's Appearance page. Quickshell writes the choice
-- to a state file and runs `hyprctl reload config-only`, which re-runs this
-- file -- so the setting survives a restart without the repo's config being
-- rewritten. "fast" halves every speed below (speed is a duration, so lower is
-- quicker) and "off" turns animations off entirely.
local function neutrinoState(name, default)
    local f = io.open(os.getenv("HOME") .. "/.local/state/neutrino/" .. name)
    if not f then return default end
    local v = f:read("l")
    f:close()
    return v or default
end
local animMode   = neutrinoState("animations", "normal")
local animFactor = animMode == "fast" and 0.5 or 1

local function animation(t)
    t.speed   = t.speed * animFactor
    t.enabled = t.enabled and animMode ~= "off"
    hl.animation(t)
end

------------------
---- MONITORS ----
------------------

-- Empty output matches every display, which is what you want on a laptop that
-- gets docked. `hyprctl monitors` for real names when you need a per-display
-- rule.
-- scale 1 is native resolution: everything as small as the panel can draw it.
-- "auto" picks a HiDPI factor on a dense laptop panel, which makes the whole
-- desktop look oversized. Nudge to 1.25 or 1.5 if 1 is too small; fractional
-- values below 1 are not supported.
hl.monitor({
    output   = "",
    mode     = "preferred",
    position = "auto",
    scale    = 1,
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
hl.env("XCURSOR_SIZE", "20")
hl.env("HYPRCURSOR_THEME", "Bibata-Modern-Classic")
hl.env("HYPRCURSOR_SIZE", "20")
-- Icon theme for Quickshell's window icons and Applications list. GTK and
-- wofi get kora from gtk settings.ini, but Quickshell is Qt and Qt has no
-- theme configured here, so without this it falls back to each app's stock
-- hicolor icon (Thunar's hammer instead of kora's folder). It has to be in
-- the environment at launch: Quickshell reads it before its own
-- `//@ pragma Env` lines are applied, so setting it from shell.qml is ignored.
hl.env("QS_ICON_THEME", "kora")

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    -- Not UWSM, so graphical-session.target is never reached on its own --
    -- nothing here ever calls `systemctl --user start` on it, so anything
    -- that relies purely on the target (rather than D-Bus activation) to
    -- launch just sits enabled and dead for the whole session. That was
    -- silently true of the polkit agent: this used to point at
    -- /usr/lib/polkit-kde-authentication-agent-1, a KDE path that doesn't
    -- exist on this system, so the exec failed instantly and quietly and
    -- no agent ever ran -- any privileged action (mounting a drive, a
    -- NetworkManager prompt) would hang waiting on a dialog that could
    -- never appear. hyprpolkitagent is the one actually installed, and
    -- it's already enabled against graphical-session.target, so starting
    -- it here rather than execing the binary directly reuses that unit
    -- (respawn-on-crash, proper cgroup) instead of running it bare.
    --
    -- reset-failed first, for when this runs after Hyprland has crashed and
    -- been restarted by its watchdog. In the seconds with no compositor the
    -- unit's Restart=on-failure respawns the agent into a missing Wayland
    -- socket until systemd's start limit trips, and from then on a plain
    -- `start` is refused ("Start request repeated too quickly") -- which left
    -- the session with no polkit agent after a crash.
    hl.exec_cmd("systemctl --user reset-failed hyprpolkitagent.service; systemctl --user start hyprpolkitagent.service")
    -- Same trap as the polkit agent: hypridle's packaged unit hangs off
    -- graphical-session.target, which never activates here, so it has to
    -- be started by hand (reset-failed for the same crash-restart reason).
    -- The fallback runs the binary bare if the unit ever goes missing,
    -- rather than leaving the machine with no idle.
    hl.exec_cmd("systemctl --user reset-failed hypridle.service; systemctl --user start hypridle.service || hypridle")
    hl.exec_cmd("quickshell")
    -- env alone does not retheme the cursor Hyprland draws over the desktop
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 20")
    -- the saved wallpaper, or a random one from wallpapers/ when shuffle is on
    hl.exec_cmd("~/.config/hypr/wallpaper.sh")
    -- A terminal waiting on workspace 2. The custom class is what scopes the
    -- "send it to 2, silently" rule below to this one instance: matching on
    -- Alacritty itself would banish every terminal you ever open.
    hl.exec_cmd(terminal .. " --class neutrino-startup")
end)

-----------------------
---- LOOK AND FEEL ----
-----------------------

hl.config({
    general = {
        gaps_in     = 1,
        gaps_out    = 0,
        border_size = 0,

        col = {
            active_border   = "rgba(c2c2c266)",
            inactive_border = "rgba(303030aa)",
        },

        resize_on_border = true,
        allow_tearing    = false,
        layout           = "dwindle",
    },

    decoration = {
        rounding         = 3,
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
        enabled = animMode ~= "off",
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

-- speed is in 100ms units (3 = 300ms), so lower is faster
animation({ leaf = "global",     enabled = true, speed = 3, bezier = "neutrino" })
animation({ leaf = "border",     enabled = true, speed = 3, bezier = "neutrino" })
animation({ leaf = "windows",    enabled = true, speed = 2, bezier = "neutrino", style = "popin 92%" })
animation({ leaf = "windowsOut", enabled = true, speed = 1.5, bezier = "neutrino", style = "popin 92%" })
animation({ leaf = "fade",       enabled = true, speed = 1.5, bezier = "neutrino" })
animation({ leaf = "workspaces", enabled = true, speed = 2, bezier = "neutrino", style = "slidefade 12%" })

-- Layer surfaces: wofi, and the bar's flyouts. These inherit `global` unless
-- set, so the launcher was taking the same 300ms a window does just to appear
-- -- long enough to feel like a delay on something you open to type into.
-- fade rather than popin: the bar is a layer too, and scaling it on every
-- start looks wrong.
animation({ leaf = "layersIn",  enabled = true, speed = 1, bezier = "neutrino", style = "fade" })
animation({ leaf = "layersOut", enabled = true, speed = 1, bezier = "neutrino", style = "fade" })

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout     = "us",
        follow_mouse  = 0,
        sensitivity   = 0.1,
        accel_profile = "adaptive",

        touchpad = {
            natural_scroll       = false,
            disable_while_typing = true,
            scroll_factor        = 1,
            -- the .conf spelling is tap-to-click; the lua schema takes the
            -- underscored form, since dashes are not a bare Lua identifier
            tap_to_click         = true,
            clickfinger_behavior = true,
        },
    },

    -- stops the cursor from jumping to whatever gets focused, e.g. the
    -- Quickshell workspace bar's click-to-focus icons
    cursor = {
        no_warps = true,
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

-- Sections are marker comments, `-- --- Name ---`: the bar's Keybinds window
-- groups binds by them and adds new ones to the end of the chosen section.

local mod = "SUPER"

-- --- Launchers ---
hl.bind("CTRL + SPACE",      hl.dsp.exec_cmd(menu))
hl.bind(mod .. " + Return",  hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + A",       hl.dsp.exec_cmd(terminal))
hl.bind(mod .. " + E",       hl.dsp.exec_cmd(fileManager))
hl.bind(mod .. " + V",       hl.dsp.exec_cmd(editor))
hl.bind(mod .. " + Z",       hl.dsp.exec_cmd(zen))
hl.bind(mod .. " + F",       hl.dsp.exec_cmd(floorp))

-- --- Window Management ---
-- fullscreen and float sit on SHIFT, since plain F and V launch apps
hl.bind(mod .. " + Q",         hl.dsp.window.close())
-- Two different things, deliberately on separate binds:
--   maximize  fills the usable area, stopping below the Quickshell bar
--   fullscreen covers the entire output, bar included
hl.bind(mod .. " + SHIFT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mod .. " + CTRL + F",  hl.dsp.window.fullscreen())
-- same action as double-clicking a window's titlebar
hl.bind(mod .. " + equal",     hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mod .. " + SHIFT + V", hl.dsp.window.float({ action = "toggle" }))
hl.bind(mod .. " + SHIFT + E", hl.dsp.exit())
hl.bind(mod .. " + P",         hl.dsp.window.pseudo())
hl.bind(mod .. " + J",         hl.dsp.layout("togglesplit"))

-- --- Focus ---
hl.bind(mod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Windows-style alt-tab: hold ALT and tap Tab to step through windows (by
-- recency, current workspace only -- there is no working reverse direction
-- on this dispatcher, tested directly, so it is forward-only). Each tap
-- maximizes the window it lands on (alt-tab.sh: "cycle, then maximize if
-- not already"), so by the time you release ALT the one you landed on is
-- already full-screen -- no separate release handler needed.
hl.bind("ALT + Tab", hl.dsp.exec_cmd("~/.config/hypr/alt-tab.sh"))

-- --- Workspaces ---
for i = 1, 5 do
    hl.bind(mod .. " + " .. i,         hl.dsp.focus({ workspace = i }))
    hl.bind(mod .. " + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end

-- --- Mouse ---
hl.bind(mod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- --- Screenshot ---
-- saves to ~/Pictures/Screenshots and copies to the clipboard
hl.bind("Print", hl.dsp.exec_cmd("~/.config/hypr/screenshot.sh"))

-- --- Function Keys ---
hl.bind("XF86AudioRaiseVolume",  hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume",  hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",         hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true })
hl.bind("XF86AudioMicMute",      hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd("brightnessctl -n1 set 5%+"),                     { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("brightnessctl -n1 set 5%-"),                     { locked = true, repeating = true })

----------------------
---- WINDOW RULES ----
----------------------

-- Deliberately NOT suppressing maximize events. Hyprland's own example config
-- ships a `suppress_event = "maximize"` rule matching class ".*", but that is
-- what double-clicking a titlebar sends: with it in place, double-click stops
-- maximizing anything. Leaving it out keeps that working, and maximize honours
-- the Quickshell bar's reserved zone, so the window fills the space below it.

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


-- The startup terminal, parked on workspace 2. "silent" is the whole point:
-- without it the window pulls the session onto workspace 2 as it opens, and
-- you land in a terminal instead of an empty desktop.
hl.window_rule({
    name  = "startup-terminal",
    match = { class = "^(neutrino-startup)$" },
    workspace = "2 silent",
})

-- Monocle. Hyprland ships dwindle and master only, with no monocle layout,
-- so this emulates one: dwindle stays the underlying layout and every tiled
-- window opens maximized, so one window is visible at a time and focus never
-- resizes anything.
--
-- Global rather than local on purpose: layout-toggle.sh flips it through
-- `hyprctl eval`, which shares this Lua state, and a local would be out of
-- scope there.

NeutrinoMonocleRule = hl.window_rule({
    name  = "monocle",
    match = { float = false },
    maximize = true,
})

-- The bar's standalone windows (System, Keybinds, Settings) are
-- Quickshell FloatingWindows, class org.quickshell. They size themselves to
-- their content, so they float at that size, centred on the focused monitor.
--
-- Two things here are load-bearing. maximize = false: the monocle rule
-- matches `float = false`, and at map time these aren't floating *yet*, so
-- it catches them too. And this rule has to come *after* the monocle rule:
-- when two rules set the same property the later one wins, so above it,
-- monocle's maximize = true overrides this and they float at full size.
hl.window_rule({
    name     = "quickshell-windows",
    match    = { class = "^(org\\.quickshell)$" },
    float    = true,
    center   = true,
    maximize = false,
})

-- SUPER+M switches between monocle and dwindle. alt-tab.sh reads the same
-- state, so in dwindle mode it only moves focus instead of maximizing.
hl.bind(mod .. " + M", hl.dsp.exec_cmd("~/.config/hypr/layout-toggle.sh"))

-- Closing a window in monocle mode leaves whatever gets focus next sized by
-- the tiling underneath, which shows as the layout briefly "unfolding". This
-- puts the survivor back to full. --settle because focus does not move until
-- the closing window is actually gone.
hl.on("window.close", function()
    hl.exec_cmd("~/.config/hypr/maximize-focused.sh --settle")
end)
