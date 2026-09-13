// Neutrino - Quickshell
// ~/.config/quickshell/Settings.qml
//
// The handful of shell values the user can change at runtime, persisted to
// JSON so they survive a restart. Everything here is written from the
// control centre's Appearance page; nothing else should assign to it.
//
// Theme reads these rather than exposing them directly, so the rest of the
// shell keeps importing one geometry source (Theme.barHeight) and doesn't
// have to know which values happen to be user-editable this week.
//
// Persistence is FileView + JsonAdapter: onAdapterUpdated fires whenever a
// property on the adapter changes, so a write follows every edit without
// any call site remembering to save. watchChanges + reload() is the other
// half -- editing the file by hand (or a second shell instance writing it)
// is picked up live rather than being silently overwritten.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // "top" or "bottom" -- which screen edge the bar is anchored to
    readonly property alias barPosition: adapter.barPosition
    readonly property alias barHeight:   adapter.barHeight
    readonly property alias moduleGap:   adapter.moduleGap
    readonly property alias radius:      adapter.radius
    readonly property alias barOpacity:  adapter.barOpacity
    readonly property alias fontScale:   adapter.fontScale
    // "normal", "fast" or "off"
    readonly property alias animSpeed:   adapter.animSpeed
    // "grayscale" or "wallpaper"
    readonly property alias colourMode:  adapter.colourMode
    // a matugen scheme type; only read in wallpaper mode
    readonly property alias colourScheme: adapter.colourScheme
    // pick a random wallpaper at login instead of restoring the last one.
    // Mirrored into the wallpaper state file by Wallpaper.qml, since the
    // login script can't read this JSON.
    readonly property alias wallpaperShuffle: adapter.wallpaperShuffle

    // Cycled through by the Appearance page's choice rows, in this order.
    readonly property var choices: ({
        animSpeed:    ["normal", "fast", "off"],
        colourMode:   ["grayscale", "wallpaper"],
        colourScheme: ["scheme-neutral", "scheme-tonal-spot", "scheme-vibrant", "scheme-expressive"],
    })
    readonly property var choiceLabels: ({
        "normal": "Normal", "fast": "Fast", "off": "Off",
        "grayscale": "Grayscale", "wallpaper": "Wallpaper",
        "scheme-neutral": "Subtle", "scheme-tonal-spot": "Balanced",
        "scheme-vibrant": "Vivid", "scheme-expressive": "Expressive",
    })

    function cycle(key) {
        var list = choices[key]
        adapter[key] = list[(list.indexOf(adapter[key]) + 1) % list.length]
    }

    function setWallpaperShuffle(on) { adapter.wallpaperShuffle = on }
    // Night Light colour temperature in kelvin. Lower is warmer. Lives here
    // for persistence only -- it isn't part of Appearance, so reset() and
    // isDefault below leave it alone.
    readonly property alias nightLightKelvin: adapter.nightLightKelvin
    // "F" or "C", switched from the weather flyout
    readonly property alias weatherUnits: adapter.weatherUnits
    function setWeatherUnits(u) { adapter.weatherUnits = (u === "C") ? "C" : "F" }

    // --- Bar Widgets ---------------------------------------------------
    // Order and visibility of the bar's modules, edited from the Control
    // Centre's Bar Widgets page. Stored as what the user changed, and read
    // back only through widgetOrder()/widgetVisible(), which reconcile it
    // against the defaults below -- so a module added to the bar in a later
    // update still appears, instead of being missing from a saved order that
    // predates it.

    readonly property var widgetDefaults: ({
        left:   ["controlcentre", "workspaces", "overview", "windows"],
        centre: ["visualizer", "media", "clock", "weather"],
        right:  ["privacy", "failed", "updates", "notifications", "tray",
                 "bluetooth", "network", "volume", "brightness", "battery"],
    })

    // Can't be hidden: the control centre button is the only way back to
    // the page that would un-hide it.
    readonly property var lockedWidgets: ["controlcentre"]

    readonly property var widgetSections: ["left", "centre", "right"]

    // The effective layout: every known module in exactly one section, in
    // order. A module goes where it was saved (first section wins if a hand
    // edit lists it twice). Unknown keys in the file are dropped.
    //
    // A module that was never saved -- added to the bar since the layout was
    // written -- goes beside its default neighbours: before the next module
    // that follows it in the defaults, or after the one before it, or at the
    // end if neither is in that section. Appending instead would put every
    // new module after the battery at the far edge.
    function widgetLayout() {
        var saved = adapter.barLayout || {}
        var known = [], homeOf = {}
        for (var s0 = 0; s0 < widgetSections.length; s0++) {
            var d = widgetDefaults[widgetSections[s0]]
            for (var k = 0; k < d.length; k++) { known.push(d[k]); homeOf[d[k]] = widgetSections[s0] }
        }
        var out = { left: [], centre: [], right: [] }, placed = {}
        for (var s1 = 0; s1 < widgetSections.length; s1++) {
            var sec = widgetSections[s1]
            var list = saved[sec] || []
            for (var i = 0; i < list.length; i++) {
                var key = list[i]
                if (known.indexOf(key) === -1 || placed[key]) continue
                out[sec].push(key)
                placed[key] = true
            }
        }
        for (var j = 0; j < known.length; j++) {
            var key2 = known[j]
            if (placed[key2]) continue
            var home = homeOf[key2], defs = widgetDefaults[home], row = out[home]
            var at = -1, di = defs.indexOf(key2)
            for (var a = di + 1; a < defs.length && at < 0; a++)
                if (placed[defs[a]] && row.indexOf(defs[a]) !== -1) at = row.indexOf(defs[a])
            for (var b = di - 1; b >= 0 && at < 0; b--)
                if (placed[defs[b]] && row.indexOf(defs[b]) !== -1) at = row.indexOf(defs[b]) + 1
            if (at < 0) row.push(key2)
            else row.splice(at, 0, key2)
            placed[key2] = true
        }
        return out
    }

    function widgetOrder(section) {
        return widgetLayout()[section] || []
    }

    function widgetSection(key) {
        var l = widgetLayout()
        for (var i = 0; i < widgetSections.length; i++)
            if (l[widgetSections[i]].indexOf(key) !== -1) return widgetSections[i]
        return "left"
    }

    function widgetVisible(key) {
        return lockedWidgets.indexOf(key) !== -1
            || (adapter.barHidden || []).indexOf(key) === -1
    }

    function setWidgetVisible(key, on) {
        if (lockedWidgets.indexOf(key) !== -1) return
        var h = (adapter.barHidden || []).filter(k => k !== key)
        if (!on) h.push(key)
        adapter.barHidden = h
    }

    // The whole layout at once, since a move between sections changes two
    // of them. A fresh object, not a mutation: the adapter only notices --
    // and writes, and the bar only repositions -- on reassignment.
    function setWidgetLayout(layout) {
        adapter.barLayout = {
            left:   (layout.left   || []).slice(),
            centre: (layout.centre || []).slice(),
            right:  (layout.right  || []).slice(),
        }
    }

    // The centre module pinned to the exact middle of the bar. The other
    // centre modules stack outward from it -- those before it in the order to
    // its left, those after to its right -- so a media title appearing never
    // nudges the clock. "" (or a module that isn't in the centre, or is
    // hidden) centres the whole group instead.
    readonly property alias centreAnchor: adapter.centreAnchor
    function setCentreAnchor(key) { adapter.centreAnchor = key }

    function resetWidgets() {
        adapter.barLayout = {}
        adapter.barHidden = []
        adapter.centreAnchor = "clock"
    }

    // Reads both properties on every evaluation, with no early return. A
    // binding only re-runs when something it *read last time* changes: an
    // early `return false` on a hidden widget skipped reading the order, so
    // resetting the order afterwards never re-ran this and it stuck at false.
    readonly property bool widgetsDefault: {
        var noneHidden = (adapter.barHidden || []).length === 0
            && adapter.centreAnchor === "clock"
        var ordersMatch = true
        for (var section in widgetDefaults)
            if (JSON.stringify(widgetOrder(section)) !== JSON.stringify(widgetDefaults[section]))
                ordersMatch = false
        return noneHidden && ordersMatch
    }

    // The bounds the Appearance page clamps to. Kept here next to the
    // values rather than in the menu, so a hand-edited JSON file that is
    // out of range is corrected by the same numbers the UI enforces.
    readonly property var limits: ({
        barHeight: { min: 24, max: 48 },
        moduleGap: { min: 0,  max: 12 },
        radius:    { min: 0,  max: 14 },
        barOpacity: { min: 40, max: 100 },
        fontScale: { min: 80, max: 130 },
        nightLightKelvin: { min: 2500, max: 6000 },
    })

    readonly property var defaults: ({
        barPosition: "top",
        barHeight: 34,
        moduleGap: 2,
        radius: 6,
        barOpacity: 100,
        fontScale: 100,
        animSpeed: "normal",
        colourMode: "grayscale",
        colourScheme: "scheme-tonal-spot",
    })

    function clamp(key, v) {
        var l = limits[key]
        return Math.max(l.min, Math.min(l.max, Math.round(v)))
    }

    // Single entry point for the menu, so clamping can't be forgotten at a
    // call site and every write goes through one place.
    function set(key, v) {
        if (key === "barPosition") adapter.barPosition = (v === "bottom") ? "bottom" : "top"
        else if (choices[key]) { if (choices[key].indexOf(v) !== -1) adapter[key] = v }
        else adapter[key] = clamp(key, v)
    }

    function step(key, delta) { set(key, adapter[key] + delta) }

    function reset() {
        for (var key in defaults) adapter[key] = defaults[key]
    }

    // filter, not every(): every() stops at the first difference, and a
    // binding only re-runs for what it read last time (see widgetsDefault)
    readonly property bool isDefault:
        Object.keys(defaults).filter(key => adapter[key] !== defaults[key]).length === 0

    // Quickshell hands out the state path but does not create the directory,
    // and an atomic write needs somewhere to put its temp file -- without
    // this the first save fails and the settings silently never persist.
    Process {
        running: true
        command: ["mkdir", "-p", view.path.substring(0, view.path.lastIndexOf("/"))]
    }

    // Writes are held until the first read has landed. Without this the
    // adapter's declared defaults count as an update the moment it is
    // constructed, so the very first thing the shell does on startup is
    // save 34/top/2/6 over whatever the user had -- the settings appear to
    // work until you restart, then silently reset. blockLoading makes that
    // first read synchronous, so by the time this component is complete the
    // adapter already holds the file's values and writing is safe.
    property bool ready: false

    // Writes are coalesced: a burst of changes (a reset assigns several
    // properties back to back) becomes one write a moment after the last.
    // Writing per change raced with watchChanges -- the first write's
    // change notification made the file reload *between* the writes, which
    // read the half-finished state back over the newer in-memory values. The
    // file ended up right while the running shell kept the stale one.
    Timer {
        id: saveTimer
        interval: 150
        onTriggered: view.writeAdapter()
    }

    FileView {
        id: view
        path: Quickshell.statePath("appearance.json")
        // preload, or nothing ever reads the file: a FileView is lazy and
        // only loads when someone asks for text()/data(), which nothing
        // here does -- the adapter is the only consumer. Without it the
        // saved values sit on disk and the shell silently runs on the
        // adapter's declared defaults.
        preload: true
        // ...and blocking, so the values are in the adapter before Theme
        // binds to them, rather than the bar rendering at the defaults and
        // jumping a frame later.
        blockLoading: true
        watchChanges: true
        // Expected on a fresh install: there is no file until the first
        // edit, and the defaults on the adapter are the right answer.
        printErrors: false

        // The gate opens once the first read has resolved one way or the
        // other -- loaded with the file's values, or failed because there
        // is no file yet and the declared defaults are already correct.
        // (Neither this object nor the singleton root has a Component
        // attached object to hook instead.)
        onLoaded: root.ready = true
        onLoadFailed: root.ready = true

        onFileChanged: reload()
        onAdapterUpdated: if (root.ready) saveTimer.restart()

        JsonAdapter {
            id: adapter
            property string barPosition: "top"
            property int barHeight: 34
            property int moduleGap: 2
            property int radius: 6
            property int barOpacity: 100
            property int fontScale: 100
            property string animSpeed: "normal"
            property string colourMode: "grayscale"
            property string colourScheme: "scheme-tonal-spot"
            property bool wallpaperShuffle: true
            property int nightLightKelvin: 4000
            property string weatherUnits: "F"
            property string centreAnchor: "clock"
            property var barLayout: ({})
            property var barHidden: []
        }
    }
}
