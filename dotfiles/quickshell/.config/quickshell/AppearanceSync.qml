// Neutrino - Quickshell
// ~/.config/quickshell/AppearanceSync.qml
//
// Carries the Appearance page's settings out to the apps that draw the same
// chrome as the bar -- corner radius, the palette (grayscale or wallpaper)
// and font size -- so the launcher and the notifications change with it.
//
// Everything lands in ~/.local/state/neutrino/, never in ~/.config: those
// directories are stow links into the repo, and generated files there would
// show up as changes to commit.
//
//   wofi.css    -- wofi's own stylesheet, rewritten. wofi parses CSS from a
//                  string, so it can't @import anything; hyprland.lua
//                  launches it with --style pointed here. Every grayscale
//                  ramp hex becomes the current colour for that role, and
//                  values tagged `@radius` / `@font` are recomputed.
//   swaync.css  -- CSS variables only. swaync loads its stylesheet from a
//                  path, so its style.css @imports this and uses var().

import Quickshell
import Quickshell.Io
import QtQuick

Scope {
    id: root

    readonly property string dir: Quickshell.env("HOME") + "/.local/state/neutrino"

    readonly property var roleNames: ["base", "bar", "panel", "surface", "overlay",
                                      "border", "muted", "subtext", "text", "bright"]

    function hex(c) { return String(c).substring(0, 7) }
    function px(offset) { return Math.max(0, Theme.radius - offset) + "px" }

    function renderWofi() {
        var tpl = wofiTemplate.text()
        if (!tpl) return
        var out = tpl.replace(/\d+px(\s*)\/\*\s*@radius(?:-(\d+))?\s*\*\//g,
            (m, sp, off) => px(parseInt(off || "0")) + sp + "/* @radius" + (off ? "-" + off : "") + " */")
        out = out.replace(/(\d+)px(\s*)\/\*\s*@font\s*\*\//g,
            (m, n, sp) => Theme.fs(parseInt(n)) + "px" + sp + "/* @font */")
        out = out.replace(/#[0-9a-fA-F]{6}\b/g, m => {
            var lower = m.toLowerCase()
            for (var i = 0; i < roleNames.length; i++)
                if (Theme.gray[roleNames[i]] === lower) return hex(Theme[roleNames[i]])
            return m
        })
        wofiOut.setText(out)
    }

    function renderSwaync() {
        var lines = [":root {",
            "  --neutrino-radius: " + px(0) + ";",
            "  --neutrino-radius-inner: " + px(2) + ";"]
        for (var i = 0; i < roleNames.length; i++)
            lines.push("  --n-" + roleNames[i] + ": " + hex(Theme[roleNames[i]]) + ";")
        // swaync's own sheet wants this one as a bare "r, g, b" triple
        var p = Theme.panel
        lines.push("  --noti-bg: " + Math.round(p.r * 255) + ", " + Math.round(p.g * 255) + ", " + Math.round(p.b * 255) + ";")
        // the shell's type scale (Theme.fontSmall / fontBody), so a
        // notification reads the same size as a flyout row
        var sizes = { small: 11, label: 13, body: 13, summary: 13 }
        for (var k in sizes)
            lines.push("  --n-fs-" + k + ": " + Theme.fs(sizes[k]) + "px;")
        lines.push("}")
        swayncOut.setText(lines.join("\n") + "\n")
        // only after the write has landed, or swaync re-reads the old file
        swayncReload.running = true
    }

    // Coalesced like Settings' own save: the steppers fire several steps in
    // a row, and each swaync reload re-parses its whole stylesheet.
    Timer {
        id: debounce
        interval: 200
        onTriggered: { root.renderWofi(); root.renderSwaync() }
    }

    Connections {
        target: Theme
        function onRadiusChanged() { debounce.restart() }
        function onRolesChanged() { debounce.restart() }
        function onFontScaleChanged() { debounce.restart() }
    }

    Process {
        running: true
        command: ["mkdir", "-p", root.dir]
        onExited: debounce.restart()
    }

    // watched, so editing the repo stylesheet regenerates the copy wofi uses
    FileView {
        id: wofiTemplate
        path: Quickshell.env("HOME") + "/.config/wofi/style.css"
        preload: true
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: debounce.restart()
    }

    FileView { id: wofiOut;   path: root.dir + "/wofi.css"; printErrors: false }
    FileView { id: swayncOut; path: root.dir + "/swaync.css"; printErrors: false }

    // Animation Speed reaches Hyprland through a state file its Lua config
    // reads on load, then a config-only reload (no monitor re-probe, so no
    // flicker). Written in one shell command so the reload can't run before
    // the write lands. At startup the file is only written, not reloaded:
    // Hyprland read the same value when it started.
    function writeHyprAnimations(reload) {
        hyprAnim.command = ["sh", "-c",
            'mkdir -p "$1" && printf "%s\\n" "$2" > "$1/animations"' + (reload ? " && hyprctl reload config-only" : ""),
            "sh", root.dir, Settings.animSpeed]
        hyprAnim.running = true
    }

    Connections {
        target: Settings
        function onAnimSpeedChanged() { root.writeHyprAnimations(true) }
    }

    Component.onCompleted: writeHyprAnimations(false)

    Process { id: hyprAnim }

    Process {
        id: swayncReload
        command: ["swaync-client", "--reload-css", "--skip-wait"]
    }
}
