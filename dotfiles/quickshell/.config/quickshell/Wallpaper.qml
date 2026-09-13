// Neutrino - Quickshell
// ~/.config/quickshell/Wallpaper.qml
//
// The wallpaper, and the colours taken from it.
//
// hypr/wallpaper.sh does the actual work of showing an image (swaybg has no
// IPC, so each change is a new swaybg) and is what restores the choice at
// login. This keeps the list, the current image, and the saved choice the
// script reads back.
//
// In wallpaper colour mode, matugen turns the image into a Material palette,
// which is mapped onto the grayscale ramp's roles -- dark surface tones for
// the grounds, outlines for the strokes, the primary tone for "bright" -- so
// every component keeps asking Theme for the same names. The result is
// cached with the image and scheme it came from: matugen takes about half a
// second, and without the cache every shell start would draw one grey frame
// before the colours arrived.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    readonly property string script: Quickshell.env("HOME") + "/.config/hypr/wallpaper.sh"
    readonly property string stateDir: Quickshell.env("HOME") + "/.local/state/neutrino"

    property var images: []
    property string current: ""
    readonly property int index: images.indexOf(current)
    readonly property string name: current === "" ? "" : current.substring(current.lastIndexOf("/") + 1).replace(/\.[^.]+$/, "")

    // role -> "#rrggbb", or null while there's no palette for the current
    // image and scheme (Theme then stays grayscale)
    property var palette: null
    property bool generating: false

    readonly property bool wanted: Settings.colourMode === "wallpaper"
    readonly property string scheme: Settings.colourScheme

    function set(path) {
        if (!path || path === current) return
        current = path
        Quickshell.execDetached([script, "set", path])
        saveState()
    }

    function step(d) {
        if (images.length === 0) return
        var i = index < 0 ? 0 : (index + d + images.length) % images.length
        set(images[i])
    }

    function shuffle() {
        if (images.length < 2) return
        var i
        do { i = Math.floor(Math.random() * images.length) } while (images[i] === current)
        set(images[i])
    }

    function saveState() {
        if (current === "") return
        stateFile.setText("shuffle=" + (Settings.wallpaperShuffle ? 1 : 0) + "\nwallpaper=" + current + "\n")
    }

    function refresh() {
        if (!wanted || current === "") return
        if (cache.image === current && cache.scheme === scheme && cache.colors) {
            palette = cache.colors
            return
        }
        // a run already in flight is for a stale image or scheme; restarting
        // it drops that result instead of letting it land over this one
        matugen.running = false
        matugen.command = ["matugen", "image", current, "--mode", "dark", "--type", scheme,
                           "--prefer", "saturation", "--json", "hex", "--dry-run", "--quiet"]
        generating = true
        matugen.running = true
    }

    onWantedChanged: refresh()
    onSchemeChanged: refresh()
    onCurrentChanged: refresh()

    Connections {
        target: Settings
        function onWallpaperShuffleChanged() { root.saveState() }
    }

    Process {
        running: true
        command: ["mkdir", "-p", root.stateDir]
    }

    Process {
        running: true
        command: [root.script, "list"]
        stdout: StdioCollector {
            onStreamFinished: root.images = text.split("\n").filter(l => l !== "")
        }
    }

    Process {
        running: true
        command: [root.script, "current"]
        stdout: StdioCollector {
            onStreamFinished: root.current = text.trim()
        }
    }

    Process {
        id: matugen
        stdout: StdioCollector {
            onStreamFinished: {
                root.generating = false
                var c
                try { c = JSON.parse(text).colors } catch (e) { return }
                if (!c) return
                function pick(k) { return c[k].dark.color }
                var colors = {
                    base:    pick("surface_container_lowest"),
                    bar:     pick("surface"),
                    panel:   pick("surface_container_low"),
                    surface: pick("surface_container"),
                    overlay: pick("surface_container_high"),
                    border:  pick("surface_container_highest"),
                    muted:   pick("outline_variant"),
                    subtext: pick("outline"),
                    text:    pick("on_surface_variant"),
                    bright:  pick("primary"),
                }
                root.palette = colors
                root.cache = { image: root.current, scheme: root.scheme, colors: colors }
                cacheFile.setText(JSON.stringify(root.cache))
            }
        }
        onExited: code => { if (code !== 0) root.generating = false }
    }

    // What the last matugen run produced. Read before anything draws, so a
    // wallpaper-coloured shell starts wallpaper-coloured.
    property var cache: ({})

    FileView {
        id: cacheFile
        path: root.stateDir + "/palette.json"
        preload: true
        blockLoading: true
        printErrors: false
        onLoaded: {
            try { root.cache = JSON.parse(text()) } catch (e) { root.cache = {} }
            // trust the cache for the scheme before swaybg has been asked
            // which image it's showing; refresh() re-checks the image after
            if (root.wanted && root.cache.scheme === root.scheme && root.cache.colors)
                root.palette = root.cache.colors
        }
    }

    FileView { id: stateFile; path: root.stateDir + "/wallpaper.state"; printErrors: false }
}
