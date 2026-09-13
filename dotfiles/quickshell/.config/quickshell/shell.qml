// Neutrino - Quickshell
// ~/.config/quickshell/shell.qml
//
// Status bar: workspaces + window icons on the left, clock in the middle,
// system modules on the right. Same grayscale ramp as the rest of the repo
// -- nothing here is coloured, only lighter or darker.
//
// Most modules open a flyout (see FlyoutPanel.qml). Only one is ever open:
// `openFlyout` holds its name rather than each module keeping a bool, which
// makes "opening one closes the others" fall out for free and gives the
// backdrop a single thing to clear.
//
// System state comes from Quickshell's own service modules (Pipewire,
// UPower, Bluetooth) rather than by polling wpctl/upower/bluetoothctl: they
// are DBus-backed and push changes, so the bar updates the moment something
// changes instead of up to a poll interval later.
//
// Two exceptions, both because no service exists to use:
//   - brightness shells out to brightnessctl (there is no backlight service)
//   - network shells out to iwctl. Quickshell.Networking's only backend is
//     NetworkManager, and this machine runs iwd instead -- with NM absent
//     the module loads but reports "could not find an available backend",
//     so nothing would ever populate.
//
// Quickshell's QML API moves quickly. If the bar does not appear, run
// `quickshell` from a terminal inside the session: QML errors go to stderr
// with a file and line number, and they are usually a renamed import.

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Services.UPower
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Services.Mpris
import QtQuick

ShellRoot {
    id: root

    // Keep Awake, from Quick Actions. Held here rather than on a bar because
    // every screen gets its own bar, and a per-screen flag would let one
    // monitor's menu say "on" while another's says "off". Session-only on
    // purpose: waking up tomorrow with idle still inhibited is the failure
    // mode worth avoiding.
    property bool keepAwake: false

    // Night Light, from Quick Actions. hyprsunset holds the warm gamma ramp
    // for as long as it runs, and the compositor restores normal gamma the
    // moment its client disconnects -- so stopping the process *is* turning
    // it off, no second "reset" command needed. Session-only, like Keep
    // Awake, and on the root for the same one-state-for-all-screens reason.
    property bool nightLight: false
    readonly property int nightLightKelvin: Settings.nightLightKelvin
    // Retune a running hyprsunset in place. Restarting it instead would
    // drop the gamma ramp for a frame and flash the screen cold on every
    // step of the stepper.
    onNightLightKelvinChanged: if (nightLightProc.running)
        Quickshell.execDetached(["hyprctl", "hyprsunset", "temperature", String(nightLightKelvin)])
    // false until the probe below finds the binary; the toggle says so
    // instead of flipping on and silently doing nothing
    property bool hasHyprsunset: false

    // Also clears out any hyprsunset left behind by a previous shell. It is
    // a child process but outlives Quickshell being killed or crashing, and
    // an orphan keeps the screen warm while this fresh instance's toggle
    // insists Night Light is off -- with nothing in the UI able to stop it.
    Process {
        running: true
        command: ["sh", "-c", "pkill -x hyprsunset; command -v hyprsunset"]
        onExited: code => root.hasHyprsunset = (code === 0)
    }

    Process {
        id: nightLightProc
        command: ["hyprsunset", "-t", String(root.nightLightKelvin)]
        running: root.nightLight && root.hasHyprsunset
        // An exit while the toggle still says on is a crash or a refused
        // gamma handle, not a user action -- drop the toggle back so it
        // doesn't claim a warm screen that isn't there.
        onExited: if (root.nightLight) root.nightLight = false
    }

    // Standalone windows opened from the Control Centre. One each for the
    // whole session, not per screen: they're ordinary toplevels, and
    // Hyprland maps them on whichever monitor has focus.
    System { id: system }
    Keybinds { id: keybinds }
    SettingsWindow { id: settingsWindow }

    AppearanceSync {}

    // Pipewire nodes are unbound by default: audio.volume / audio.muted stay
    // invalid until the node is tracked, so the sink has to be listed here
    // for the volume module to read or write anything at all.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink]
    }

    // A new/closed/moved window's class (and so its icon) doesn't show up
    // in Hyprland.toplevels until something re-requests the full client
    // list -- it isn't pushed with the openwindow event itself. Force that
    // refetch right when it happens instead of waiting for the next
    // incidental one (e.g. a workspace switch), which is what made new
    // app icons take a while to appear.
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow" || event.name === "closewindow" || event.name === "movewindow") {
                Hyprland.refreshToplevels()
            }
        }
    }

    Variants {
        model: Quickshell.screens

        Scope {
            id: screenScope
            required property var modelData

            // name of the open flyout, "" for none
            property string openFlyout: ""
            // screen-local x the open flyout centres itself under
            property real flyoutAnchorX: 0

            // `item` is the module that was clicked; mapToItem(null, ...)
            // gives its position in its own window's coordinates, and the
            // bar and the flyouts all span the full screen width, so that
            // x is directly usable as the flyout's anchor.
            function toggleFlyout(name, item) {
                if (screenScope.openFlyout === name) {
                    screenScope.openFlyout = ""
                    return
                }
                screenScope.flyoutAnchorX = item.mapToItem(null, item.width / 2, 0).x
                screenScope.openFlyout = name
            }

            // Settings' Appearance entry opens this screen's Control Centre
            // on that page -- only on the focused screen, since every
            // screen's scope hears the one window's signal.
            Connections {
                target: settingsWindow
                function onAppearanceRequested() {
                    if (!Hyprland.focusedMonitor || Hyprland.focusedMonitor.name !== screenScope.modelData.name) return
                    screenScope.flyoutAnchorX = ccBtn.mapToItem(null, ccBtn.width / 2, 0).x
                    screenScope.openFlyout = "controlcentre"
                    controlCentre.page = "appearance"
                }
            }

        PanelWindow {
            id: bar
            screen: screenScope.modelData

            // Both edges are listed and one is switched off, rather than
            // anchoring to a single computed edge: a PanelWindow with left
            // and right but neither top nor bottom is not a valid strut, so
            // the pair has to stay mutually exclusive.
            anchors {
                top: Theme.barPosition === "top"
                bottom: Theme.barPosition === "bottom"
                left: true
                right: true
            }
            implicitHeight: Theme.barHeight
            // Transparent, with the ground drawn by the Rectangle below. A
            // Wayland surface decides whether it has an alpha channel when
            // it's created, so a window that starts opaque stays opaque --
            // assigning a translucent colour to it later does nothing. A
            // window that starts transparent can show any opacity after.
            color: "transparent"

            // Bar Opacity. Only the ground fades: the chips and their text
            // stay solid so the bar is still readable over a busy wallpaper.
            Rectangle {
                anchors.fill: parent
                color: Theme.bar
                opacity: Theme.barOpacity
            }

            readonly property PwNode sink: Pipewire.defaultAudioSink

            // UPower's DisplayDevice is a synthetic aggregate: it reports a
            // percentage but not necessarily powerSupply, so isLaptopBattery
            // is false on it and it can't be used to decide whether this
            // machine even has a battery. Prefer the real one, fall back to
            // the aggregate.
            readonly property UPowerDevice batt: {
                var ds = UPower.devices ? UPower.devices.values : []
                for (var i = 0; i < ds.length; i++) {
                    if (ds[i].isLaptopBattery) return ds[i]
                }
                return UPower.displayDevice
            }
            readonly property bool hasBattery: batt && batt.ready && batt.isPresent

            function batteryPercent() {
                return batt && batt.ready ? Math.round(batt.percentage * 100) : 0
            }

            property int brightness: 0
            property int tick: 0

            function volumePercent() {
                if (!sink || !sink.ready || !sink.audio) return 0
                return Math.round(sink.audio.volume * 100)
            }

            function volumeMuted() {
                return sink && sink.ready && sink.audio ? sink.audio.muted : false
            }

            function setVolume(pct) {
                if (!sink || !sink.ready || !sink.audio) return
                sink.audio.volume = Math.max(0, Math.min(1, pct / 100))
            }

            function setBrightness(pct) {
                // clamped at 1, not 0: brightnessctl will happily set a
                // laptop panel to fully black and leave you guessing
                var v = Math.max(1, Math.min(100, Math.round(pct)))
                brightness = v
                Quickshell.execDetached(["brightnessctl", "set", v + "%"])
            }

            function batteryIcon() {
                if (!hasBattery) return "󰁹"
                if (!UPower.onBattery) return "󰂄"
                var p = batteryPercent()
                if (p >= 90) return "󰁹"
                if (p >= 55) return "󰂀"
                if (p >= 25) return "󰁽"
                return "󰁺"
            }

            // iwd state, refreshed by the Processes at the bottom
            property string netDevice: ""
            property string netSsid: ""
            // iwd's Powered flag for the radio. Read from `device list`, not
            // `station show`: a powered-off device has no station at all
            // ("No station on device"), but still appears in the list.
            property bool netPowered: true

            function setWifiPowered(on) {
                if (netDevice === "") return
                netPowered = on    // optimistic; netPowerProc settles it
                if (!on) netSsid = ""
                netPowerSet.command = ["iwctl", "device", netDevice,
                    "set-property", "Powered", on ? "on" : "off"]
                netPowerSet.running = true
            }

            // Name of the first connected Bluetooth device, "" for none.
            function btConnectedName() {
                var a = Bluetooth.defaultAdapter
                var ds = (a && a.devices) ? a.devices.values : []
                for (var i = 0; i < ds.length; i++) {
                    if (!ds[i].connected) continue
                    return ds[i].deviceName !== "" ? ds[i].deviceName
                        : (ds[i].name !== "" ? ds[i].name : ds[i].address)
                }
                return ""
            }
            // [{ connected, ssid, security, bars, known }]
            property var netList: []

            // {source, address} for every window open on the focused
            // workspace, via each window's wmClass -> .desktop entry -> icon.
            // address lets the icon's click handler focus that exact window.
            function focusedWorkspaceIcons() {
                // read this so the binding re-evaluates once the desktop
                // entry scan (async at startup) finishes populating it
                var entryCount = DesktopEntries.applications.values.length
                if (entryCount === 0) return []

                if (!Hyprland.focusedWorkspace) return []
                var wsId = Hyprland.focusedWorkspace.id

                var icons = []
                var wss = Hyprland.workspaces.values
                for (var i = 0; i < wss.length; i++) {
                    if (wss[i].id !== wsId) continue
                    var tls = wss[i].toplevels.values
                    for (var j = 0; j < tls.length; j++) {
                        var cls = tls[j].lastIpcObject ? tls[j].lastIpcObject.class : ""
                        if (!cls || isShellWindow(tls[j])) continue
                        var entry = DesktopEntries.heuristicLookup(cls)
                        var path = entry ? Quickshell.iconPath(entry.icon, true) : ""
                        if (path) icons.push({ source: path, address: tls[j].address })
                    }
                    break
                }
                return icons
            }

            // The shell's own standalone windows (System, Keybinds)
            // are part of the bar, not apps you're running, so they're left
            // out of everything that lists windows: no Quickshell icon in the
            // window strip, no entry in the workspace flyout, and a workspace
            // holding only one of them still reads as empty.
            function isShellWindow(tl) {
                return !!(tl.lastIpcObject && tl.lastIpcObject.class === "org.quickshell")
            }

            function workspaceHasWindows(id) {
                var wss = Hyprland.workspaces.values
                for (var i = 0; i < wss.length; i++) {
                    if (wss[i].id !== id) continue
                    var tls = wss[i].toplevels.values
                    for (var j = 0; j < tls.length; j++)
                        if (!isShellWindow(tls[j])) return true
                    return false
                }
                return false
            }

            // every window on every workspace, for the workspace flyout
            function allWindows() {
                var out = []
                var wss = Hyprland.workspaces.values
                for (var i = 0; i < wss.length; i++) {
                    var tls = wss[i].toplevels.values
                    for (var j = 0; j < tls.length; j++) {
                        if (isShellWindow(tls[j])) continue
                        var ipc = tls[j].lastIpcObject
                        out.push({
                            ws: wss[i].id,
                            title: ipc && ipc.title ? ipc.title : (ipc && ipc.class ? ipc.class : "window"),
                            address: tls[j].address
                        })
                    }
                }
                out.sort(function(a, b) { return a.ws - b.ws })
                return out
            }

            // --- module slots ----------------------------------------
            // The left and right groups are laid out by hand rather than by
            // a Row, because a Row can only place children in the order they
            // are declared, and Bar Widgets lets that order be changed. Each
            // module takes its x from the saved order: the sum of the widths
            // of the visible modules before it. A hidden module takes no
            // space, so the rest close up around it.

            readonly property var widgetItems: ({
                controlcentre: ccBtn, workspaces: wsFrame, overview: wsOverviewBtn,
                windows: windowIcons, clock: clock, bluetooth: btBtn,
                network: netBtn, volume: volBtn, brightness: brightBtn,
                battery: battBtn, tray: trayFrame, media: mediaBtn,
                visualizer: vizFrame, weather: weatherBtn,
                notifications: notifBtn, privacy: privacyBtn,
                failed: failedBtn, updates: updatesBtn })

            function widgetItem(key) { return widgetItems[key] }

            // Every module lives in the slot container of its saved section,
            // at the x its saved order gives it. Bound here once rather than
            // on each module, so a module only declares what it shows.
            Component.onCompleted: {
                for (const key in widgetItems) {
                    const it = widgetItems[key]
                    it.parent = Qt.binding(() => slotsFor(Settings.widgetSection(key)))
                    it.x = Qt.binding(() => slotX(it.parent, key))
                    it.slideX = Qt.binding(() => slotsAnimate)
                }
            }

            function slotsFor(section) {
                return section === "centre" ? centreSlots
                    : section === "right" ? rightSlots : leftSlots
            }

            function slotX(slots, key) {
                if (slots === centreSlots) return centreX(key)
                var x = 0
                var o = slots.order
                for (var i = 0; i < o.length; i++) {
                    if (o[i] === key) return x
                    var it = slots.itemFor(o[i])
                    if (it && it.visible) x += it.width + Theme.moduleGap
                }
                return x
            }

            // Centre positions. With a pinned module visible in the centre,
            // it sits dead centre and the rest are measured outward from its
            // edges; otherwise the visible modules are centred as one group.
            // Rounded, since a half-pixel x blurs the chip borders.
            function centreX(key) {
                var o = centreSlots.order
                var gap = Theme.moduleGap
                var ai = o.indexOf(Settings.centreAnchor)
                var anchorItem = ai >= 0 ? widgetItem(o[ai]) : null
                var ki = o.indexOf(key)
                var x = 0, i, it

                if (!anchorItem || !anchorItem.visible) {
                    x = (centreSlots.width - slotsWidth(centreSlots)) / 2
                    for (i = 0; i < ki; i++) {
                        it = widgetItem(o[i])
                        if (it && it.visible) x += it.width + gap
                    }
                    return Math.round(x)
                }

                var ax = (centreSlots.width - anchorItem.width) / 2
                if (ki === ai) return Math.round(ax)
                if (ki > ai) {
                    x = ax + anchorItem.width + gap
                    for (i = ai + 1; i < ki; i++) {
                        it = widgetItem(o[i])
                        if (it && it.visible) x += it.width + gap
                    }
                    return Math.round(x)
                }
                // left of the anchor: step back over each module down to and
                // including this one, landing on its left edge
                x = ax
                for (i = ai - 1; i >= ki; i--) {
                    it = widgetItem(o[i])
                    if (it && (it.visible || i === ki)) x -= it.width + gap
                }
                return Math.round(x)
            }

            function slotsWidth(slots) {
                var w = 0, n = 0
                var o = slots.order
                for (var i = 0; i < o.length; i++) {
                    var it = slots.itemFor(o[i])
                    if (it && it.visible) { w += it.width; n++ }
                }
                return w + Math.max(0, n - 1) * Theme.moduleGap
            }

            // Slides modules when the order changes, but not at startup,
            // where every module would sweep in from x=0 as widths settle.
            property bool slotsAnimate: false
            Timer {
                interval: 800
                running: true
                onTriggered: bar.slotsAnimate = true
            }

            // hairline under the bar, so it reads as a surface rather than a
            // strip of background
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.border
            }

            // --- left: workspaces -------------------------------------
            Item {
                id: leftSlots
                anchors.left: parent.left
                anchors.leftMargin: Theme.moduleGap
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: bar.slotsWidth(leftSlots)

                readonly property var order: Settings.widgetOrder("left")
                function itemFor(k) { return bar.widgetItem(k) }

                // Control centre. Sits left of the workspaces, where a
                // distro/menu button conventionally lives.
                BarModule {
                    id: ccBtn
                    icon: "󰣇"
                    padH: 14
                    active: screenScope.openFlyout === "controlcentre"
                    onActivated: screenScope.toggleFlyout("controlcentre", ccBtn)
                }

                // One frame around the whole set, with the current
                // workspace shown as a widened pill rather than a number.
                // Three states read by size and weight alone: current is a
                // long bright bar, occupied a short one, empty a dim stub --
                // the same language as the gauges on the right, where how
                // much space a thing takes up is the information.
                ModuleFrame {
                    id: wsFrame
                    visible: Settings.widgetVisible("workspaces")
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    padH: 8

                    Repeater {
                        model: 5

                        Item {
                            required property int index
                            readonly property int wsId: index + 1
                            readonly property bool current: Hyprland.focusedWorkspace
                                ? Hyprland.focusedWorkspace.id === wsId
                                : false
                            readonly property bool occupied: bar.workspaceHasWindows(wsId)

                            anchors.verticalCenter: parent.verticalCenter
                            // a little wider than the pill so an empty
                            // workspace is still a comfortable click target
                            implicitWidth: pip.width + 4
                            implicitHeight: Theme.moduleHeight - 8

                            Rectangle {
                                id: pip
                                anchors.centerIn: parent
                                height: 7
                                width: parent.current ? 22 : (parent.occupied ? 11 : 7)
                                // fully rounded: half the height makes a pill
                                // at any width, and a circle at the stub size
                                radius: height / 2
                                color: parent.current ? Theme.bright
                                    : (parent.occupied ? Theme.subtext : Theme.muted)

                                Behavior on width {
                                    NumberAnimation { duration: Theme.dur(130); easing.type: Easing.OutCubic }
                                }
                                Behavior on color { ColorAnimation { duration: Theme.dur(130) } }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Hyprland.dispatch("hl.dsp.focus({workspace=" + parent.wsId + "})")
                            }
                        }
                    }
                }

                // overview of every window on every workspace
                BarModule {
                    id: wsOverviewBtn
                    visible: Settings.widgetVisible("overview")
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "󰕰"
                    active: screenScope.openFlyout === "workspaces"
                    dimmed: screenScope.openFlyout !== "workspaces"
                    onActivated: screenScope.toggleFlyout("workspaces", wsOverviewBtn)
                }

                // icons for whatever is open on the focused workspace,
                // trailing the overview button. One frame around the whole
                // row rather than one per icon: they're a single group, and
                // a chip each would read as six separate modules.
                ModuleFrame {
                    id: windowIcons
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    // an empty chip on a bare workspace would be a floating
                    // rectangle with nothing in it
                    visible: iconRepeater.count > 0 && Settings.widgetVisible("windows")

                    Repeater {
                        id: iconRepeater
                        model: bar.focusedWorkspaceIcons()

                        IconImage {
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            source: modelData.source
                            implicitSize: 18

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    // focus first, then maximize -- same
                                    // action as double-clicking the titlebar
                                    Hyprland.dispatch("hl.dsp.focus({window=\"address:0x" + parent.modelData.address + "\"})")
                                    Hyprland.dispatch("hl.dsp.window.fullscreen({mode=\"maximized\"})")
                                }
                            }
                        }
                    }
                }
            }

            // --- centre -----------------------------------------------
            // Centred on the bar as a group, so whatever is moved in here
            // stays balanced around the middle of the screen.
            // Spans the whole bar, so positions inside it are bar positions
            // and "the middle" is simply half its width. It holds no input
            // handlers of its own, so it doesn't block clicks on either side.
            Item {
                id: centreSlots
                anchors.fill: parent

                readonly property var order: Settings.widgetOrder("centre")
                function itemFor(k) { return bar.widgetItem(k) }
            }

            // Time and date in one chip. Everything except "|" in the format
            // string is a QDateTime specifier; the pipe and spaces pass
            // through untouched.
            BarModule {
                id: clock
                visible: Settings.widgetVisible("clock")
                label: Qt.formatDateTime(new Date(), "HH:mm:ss  |  MM/dd/yy")
                active: screenScope.openFlyout === "calendar"
                onActivated: screenScope.toggleFlyout("calendar", clock)
            }

            // --- right: system modules --------------------------------
            // All icons come from the Material Design set rather than a mix
            // of icon families: Font Awesome's bluetooth glyph in particular
            // is far narrower and taller than its speaker/wifi/battery, so a
            // mixed row never looks evenly weighted.
            // Tight gaps: the chips' own borders already separate them, so
            // a wide gap on top of that just scatters the row.
            Item {
                id: rightSlots
                anchors.right: parent.right
                anchors.rightMargin: Theme.moduleGap
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: bar.slotsWidth(rightSlots)

                readonly property var order: Settings.widgetOrder("right")
                function itemFor(k) { return bar.widgetItem(k) }

                BarModule {
                    id: btBtn
                    visible: Settings.widgetVisible("bluetooth")
                    readonly property var adapter: Bluetooth.defaultAdapter
                    icon: (adapter && adapter.enabled) ? "󰂯" : "󰂲"
                    active: screenScope.openFlyout === "bluetooth"
                    dimmed: !(adapter && adapter.enabled)
                    onActivated: screenScope.toggleFlyout("bluetooth", btBtn)
                }

                BarModule {
                    id: netBtn
                    visible: Settings.widgetVisible("network")
                    // the filled strength glyph, not the outlined md-wifi
                    // arcs: its neighbours (volume, battery, power) are all
                    // solid, and the thin one read as a different weight
                    icon: bar.netSsid !== "" ? "󰤨" : "󰤮"
                    active: screenScope.openFlyout === "network"
                    dimmed: bar.netSsid === ""
                    onActivated: {
                        // scan on open rather than on a timer: the radio
                        // should not sweep while nobody is looking at it
                        netScan.running = true
                        screenScope.toggleFlyout("network", netBtn)
                    }
                }

                BarModule {
                    id: volBtn
                    visible: Settings.widgetVisible("volume")
                    fixedWidth: Theme.moduleWidth
                    // the bar carries the level now, so the icon only has
                    // to say muted or not -- and those two glyphs are the
                    // same width, so the chip no longer resizes as you scroll
                    icon: bar.volumeMuted() ? "󰖁" : "󰕾"
                    fillValue: bar.volumeMuted() ? 0 : bar.volumePercent() / 100
                    active: screenScope.openFlyout === "volume"
                    acceptWheel: true
                    onActivated: screenScope.toggleFlyout("volume", volBtn)
                    onMiddleClicked: {
                        if (bar.sink && bar.sink.ready && bar.sink.audio)
                            bar.sink.audio.muted = !bar.sink.audio.muted
                    }
                    onWheeled: d => bar.setVolume(bar.volumePercent() + d * 5)
                }

                BarModule {
                    id: brightBtn
                    visible: Settings.widgetVisible("brightness")
                    fixedWidth: Theme.moduleWidth
                    icon: "󰃠"
                    fillValue: bar.brightness / 100
                    active: screenScope.openFlyout === "brightness"
                    acceptWheel: true
                    onActivated: screenScope.toggleFlyout("brightness", brightBtn)
                    onWheeled: d => bar.setBrightness(bar.brightness + d * 5)
                }

                BarModule {
                    id: battBtn
                    fixedWidth: Theme.moduleWidth
                    visible: bar.hasBattery && Settings.widgetVisible("battery")
                    // charging is all the glyph still needs to say; the
                    // level is the bar's job
                    icon: UPower.onBattery ? "󰁹" : "󰂄"
                    fillValue: bar.batteryPercent() / 100
                    // Charging wins over the low warning on purpose: at 8%
                    // and plugged in, the useful fact is that it's recovering.
                    fillColor: {
                        if (!UPower.onBattery) return Theme.good
                        if (bar.batteryPercent() <= 15) return Theme.alert
                        return Theme.muted
                    }
                    active: screenScope.openFlyout === "battery"
                    onActivated: {
                        PpdProfile.refresh()
                        screenScope.toggleFlyout("battery", battBtn)
                    }
                }

                // ---- contextual modules ---------------------------------
                // Everything below except weather and the tray appears only
                // while it has something to say: media while a player is
                // open, the visualizer while sound is playing, and the
                // alert-style ones (privacy, failed units, updates, unread
                // notifications) only when there's something to act on.
                // Bar Widgets can still turn any of them off entirely.

                // system tray: one frame around every app's icon, like the
                // open-windows strip. Left activates, right opens the app's
                // menu in a flyout, middle is the app's secondary action.
                ModuleFrame {
                    id: trayFrame
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6
                    visible: trayRepeater.count > 0 && Settings.widgetVisible("tray")
                    active: screenScope.openFlyout === "traymenu"

                    Repeater {
                        id: trayRepeater
                        model: SystemTray.items.values

                        IconImage {
                            id: trayIcon
                            required property var modelData
                            anchors.verticalCenter: parent.verticalCenter
                            source: modelData.icon
                            implicitSize: 16

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => {
                                    var item = trayIcon.modelData
                                    if (mouse.button === Qt.MiddleButton) {
                                        item.secondaryActivate()
                                    } else if (mouse.button === Qt.RightButton || item.onlyMenu) {
                                        if (!item.hasMenu) return
                                        trayMenu.item = item
                                        trayMenu.stack = []
                                        screenScope.toggleFlyout("traymenu", trayIcon)
                                    } else {
                                        item.activate()
                                    }
                                }
                            }
                        }
                    }
                }

                BarModule {
                    id: mediaBtn
                    readonly property var player: Media.player
                    visible: player !== null && Settings.widgetVisible("media")
                    icon: player && player.isPlaying ? "󰏤" : "󰐊"
                    label: !player ? ""
                        : (player.trackArtist ? player.trackArtist + " – " : "") + (player.trackTitle || player.identity)
                    labelMaxWidth: 220
                    active: screenScope.openFlyout === "media"
                    onActivated: screenScope.toggleFlyout("media", mediaBtn)
                    onMiddleClicked: if (player && player.canTogglePlaying) player.togglePlaying()
                }

                // audio spectrum: thin pills growing from the middle, in the
                // same shape language as the workspace indicator
                ModuleFrame {
                    id: vizFrame
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    padH: 8
                    visible: Visualizer.playing && Settings.widgetVisible("visualizer")

                    Repeater {
                        model: Visualizer.barCount

                        Item {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            implicitWidth: 3
                            implicitHeight: Theme.moduleHeight - 10

                            Rectangle {
                                anchors.centerIn: parent
                                width: 3
                                radius: 1.5
                                readonly property real v: (Visualizer.bars[parent.index] || 0) / 100
                                height: Math.max(3, parent.height * v)
                                color: Theme.text
                                Behavior on height { NumberAnimation { duration: Theme.dur(60) } }
                            }
                        }
                    }
                }

                BarModule {
                    id: weatherBtn
                    visible: Weather.ready && Settings.widgetVisible("weather")
                    icon: Weather.iconFor(Weather.code, Weather.isNight)
                    label: Weather.temp(Weather.tempF, Weather.tempC)
                    active: screenScope.openFlyout === "weather"
                    onActivated: screenScope.toggleFlyout("weather", weatherBtn)
                }

                BarModule {
                    id: notifBtn
                    // always shown, so the panel is one click away even when
                    // it's empty; dimmed when there's nothing unread
                    visible: Settings.widgetVisible("notifications")
                    icon: Notifications.dnd ? "󰂛" : "󰂚"
                    label: Notifications.count > 0 ? String(Notifications.count) : ""
                    dimmed: Notifications.dnd || Notifications.count === 0 || !Notifications.available
                    // left: swaync's panel; right: Do Not Disturb
                    onActivated: Notifications.togglePanel()
                    onRightClicked: Notifications.toggleDnd()
                }

                BarModule {
                    id: privacyBtn
                    visible: Privacy.active && Settings.widgetVisible("privacy")
                    // one glyph per kind of capture in progress
                    icon: [Privacy.mic ? "󰍬" : "", Privacy.camera ? "󰄀" : "", Privacy.screen ? "󰍹" : ""]
                        .filter(g => g !== "").join(" ")
                    // the palette's alert hue, on purpose: this is the one
                    // module that exists to be noticed
                    iconColor: Theme.alert
                    active: screenScope.openFlyout === "privacy"
                    onActivated: screenScope.toggleFlyout("privacy", privacyBtn)
                }

                BarModule {
                    id: failedBtn
                    visible: FailedUnits.count > 0 && Settings.widgetVisible("failed")
                    icon: "󰀦"
                    iconColor: Theme.alert
                    label: String(FailedUnits.count)
                    active: screenScope.openFlyout === "failed"
                    onActivated: {
                        FailedUnits.refresh()
                        screenScope.toggleFlyout("failed", failedBtn)
                    }
                }

                BarModule {
                    id: updatesBtn
                    visible: Updates.count > 0 && Settings.widgetVisible("updates")
                    icon: "󰚰"
                    label: String(Updates.count)
                    active: screenScope.openFlyout === "updates"
                    onActivated: screenScope.toggleFlyout("updates", updatesBtn)
                }
            }

            // --- data -------------------------------------------------
            // Brightness is read straight from sysfs and *watched*, not
            // polled: the backlight attribute emits change notifications, so
            // the readout follows the XF86MonBrightness keys (and anything
            // else that writes to it) the same way the Pipewire-backed volume
            // readout follows external volume changes. brightnessctl is still
            // used to write, since sysfs isn't user-writable.
            property string backlightDir: ""
            property int brightnessMax: 0

            Process {
                id: backlightFind
                command: ["sh", "-c", "ls -d /sys/class/backlight/*/ 2>/dev/null | head -1"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: bar.backlightDir = text.trim().replace(/\/$/, "")
                }
            }

            FileView {
                id: brightnessMaxFile
                path: bar.backlightDir !== "" ? bar.backlightDir + "/max_brightness" : ""
                onLoaded: {
                    var v = parseInt(text().trim())
                    if (!isNaN(v) && v > 0) {
                        bar.brightnessMax = v
                        brightnessFile.reload()
                    }
                }
            }

            FileView {
                id: brightnessFile
                path: bar.backlightDir !== "" ? bar.backlightDir + "/brightness" : ""
                watchChanges: true
                onFileChanged: reload()
                onLoaded: {
                    var raw = parseInt(text().trim())
                    if (!isNaN(raw) && bar.brightnessMax > 0)
                        bar.brightness = Math.round(raw / bar.brightnessMax * 100)
                }
            }

            // --- iwd ---------------------------------------------
            // iwctl draws tables for humans: ANSI colour, a banner, and
            // fixed-width columns. Everything below strips the escapes and
            // cuts by column offset rather than by whitespace, because SSIDs
            // are allowed to contain spaces and would break field splitting.

            Process {
                id: netDeviceProc
                command: ["sh", "-c",
                    "iwctl device list 2>/dev/null | sed 's/\\x1b\\[[0-9;]*m//g' "
                    + "| awk 'NR>4 && $5==\"station\" {print $1; exit}'"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: {
                        bar.netDevice = text.trim()
                        if (bar.netDevice !== "") {
                            netStatus.running = true
                            netPowerProc.running = true
                        }
                    }
                }
            }

            Process {
                id: netStatus
                command: ["sh", "-c",
                    "iwctl station " + bar.netDevice + " show 2>/dev/null "
                    + "| sed 's/\\x1b\\[[0-9;]*m//g' "
                    + "| awk -F'  +' '/Connected network/ {print $3}'"]
                stdout: StdioCollector {
                    onStreamFinished: bar.netSsid = text.trim()
                }
            }

            Process {
                id: netScan
                command: ["sh", "-c",
                    "iwctl station " + bar.netDevice + " scan 2>/dev/null; sleep 2"]
                onExited: {
                    netStatus.running = true
                    netListProc.running = true
                }
            }

            Process {
                id: netListProc
                command: ["sh", "-c",
                    "known=$(iwctl known-networks list 2>/dev/null "
                    + "| sed 's/\\x1b\\[[0-9;]*m//g' | awk 'NR>4 {n=substr($0,3,34); "
                    + "gsub(/^ +| +$/,\"\",n); if (n!=\"\") print n}'); "
                    + "iwctl station " + bar.netDevice + " get-networks 2>/dev/null "
                    + "| sed 's/\\x1b\\[[0-9;]*m//g' "
                    + "| awk -v known=\"$known\" 'BEGIN{split(known,k,\"\\n\")} "
                    + "NR>4 && length($0)>10 { "
                    + "marker=substr($0,1,6); name=substr($0,7,34); "
                    + "sec=substr($0,41,20); sig=substr($0,61); "
                    + "gsub(/^ +| +$/,\"\",marker); gsub(/^ +| +$/,\"\",name); "
                    + "gsub(/^ +| +$/,\"\",sec); gsub(/^ +| +$/,\"\",sig); "
                    + "if (name==\"\") next; kn=0; for (i in k) if (k[i]==name) kn=1; "
                    + "printf \"%s|%s|%s|%d|%s\\n\", (marker==\">\"?\"1\":\"0\"), "
                    + "name, sec, length(sig), kn }'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        var out = []
                        var lines = text.split("\n")
                        for (var i = 0; i < lines.length; i++) {
                            var f = lines[i].split("|")
                            if (f.length < 5) continue
                            out.push({
                                connected: f[0] === "1",
                                ssid: f[1],
                                security: f[2],
                                bars: parseInt(f[3]) || 0,
                                known: f[4] === "1"
                            })
                        }
                        bar.netList = out
                    }
                }
            }

            Process {
                id: netPowerProc
                command: ["sh", "-c",
                    "iwctl device list 2>/dev/null | sed 's/\\x1b\\[[0-9;]*m//g' "
                    + "| awk 'NR>4 && $1==\"" + bar.netDevice + "\" {print $3; exit}'"]
                stdout: StdioCollector {
                    onStreamFinished: {
                        var v = text.trim()
                        if (v !== "") bar.netPowered = (v === "on")
                    }
                }
            }

            // Powering the radio back on doesn't hand back an SSID at once:
            // iwd reconnects to a known network about a second later. So the
            // status is re-read after a short wait instead of on exit, or the
            // row would say "Not connected" until the next 15s refresh.
            Process {
                id: netPowerSet
                command: ["true"]
                onExited: {
                    netPowerProc.running = true
                    netPowerSettle.restart()
                }
            }

            Timer {
                id: netPowerSettle
                interval: 2500
                onTriggered: netStatus.running = true
            }

            // command is rewritten per click, so it starts out empty
            Process {
                id: netConnect
                command: ["true"]
                onExited: {
                    netStatus.running = true
                    netListProc.running = true
                }
            }

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    clock.label = Qt.formatDateTime(new Date(), "HH:mm:ss  |  MM/dd/yy")
                    bar.tick++
                    // iwd reports itself active before its interfaces are
                    // registered, so the one-shot probe at startup can come
                    // back empty. The SSID refresh below is gated on having a
                    // device, so without this retry that empty result sticks
                    // for the whole session and the bar insists it is offline
                    // while the machine is plainly online.
                    if (bar.netDevice === "") {
                        if (bar.tick % 5 === 0) netDeviceProc.running = true
                    } else if (bar.tick % 15 === 0) {
                        // the SSID only changes when you move between
                        // networks, so it doesn't need a per-second iwctl call
                        netStatus.running = true
                        netPowerProc.running = true
                    }
                }
            }

            // Keep Awake. The Wayland idle-inhibit protocol, rather than
            // `systemd-inhibit`: idle daemons (hypridle and friends) watch
            // this protocol, and it needs no process kept alive. It only
            // holds while its window is mapped, which is why it hangs off the
            // bar -- the one surface that is always up.
            IdleInhibitor {
                window: bar
                enabled: root.keepAwake
            }
        }

        // --- flyouts --------------------------------------------------
        // Each is its own layer-shell surface rather than something drawn
        // inside the bar: a panel clips to its own surface, so a dropdown
        // drawn in the bar would be cut off at the bar's bottom edge.

        // workspaces / windows
        FlyoutPanel {
            scope: screenScope
            flyout: "workspaces"
            menuWidth: 280

            FlyoutHeading { text: "WINDOWS" }

            Repeater {
                model: bar.allWindows()

                FlyoutRow {
                    required property var modelData
                    label: "[" + modelData.ws + "] " + modelData.title
                    onActivated: {
                        screenScope.openFlyout = ""
                        Hyprland.dispatch("hl.dsp.focus({window=\"address:0x" + modelData.address + "\"})")
                    }
                }
            }

            FlyoutRow {
                label: "No windows open"
                enabled: false
                visible: bar.allWindows().length === 0
            }
        }

        // calendar
        FlyoutPanel {
            id: calendarFlyout
            scope: screenScope
            flyout: "calendar"
            menuWidth: 240

            // offset in months from the current one, so the flyout can page
            // back and forth without tracking a whole date
            property int monthOffset: 0
            readonly property date shown: {
                var d = new Date()
                return new Date(d.getFullYear(), d.getMonth() + monthOffset, 1)
            }

            // reset to this month every time it opens, so it never comes
            // back up three months deep from last time
            onOpenChanged: if (open) monthOffset = 0

            Item {
                width: parent.width
                height: 20

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "‹"
                    color: Theme.subtext
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontLarge
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calendarFlyout.monthOffset--
                    }
                }

                Text {
                    anchors.centerIn: parent
                    text: Qt.formatDateTime(calendarFlyout.shown, "MMMM yyyy").toUpperCase()
                    color: Theme.bright
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontBody
                    font.bold: true
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "›"
                    color: Theme.subtext
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontLarge
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: calendarFlyout.monthOffset++
                    }
                }
            }

            Grid {
                width: parent.width
                columns: 7
                spacing: 0

                Repeater {
                    model: ["M", "T", "W", "T", "F", "S", "S"]

                    Text {
                        required property var modelData
                        width: calendarFlyout.contentColumn.width / 7
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData
                        color: Theme.muted
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontSmall
                    }
                }

                Repeater {
                    // 42 cells = 6 weeks, enough for any month/start-day
                    // combination, so the grid never reflows height
                    model: 42

                    Item {
                        required property int index
                        width: calendarFlyout.contentColumn.width / 7
                        height: 22

                        // Monday-first: JS getDay() is Sunday-first, so
                        // Sunday (0) becomes 6 and everything else shifts
                        // down one.
                        readonly property int firstDow: {
                            var d = calendarFlyout.shown.getDay()
                            return d === 0 ? 6 : d - 1
                        }
                        readonly property int daysInMonth: {
                            var s = calendarFlyout.shown
                            return new Date(s.getFullYear(), s.getMonth() + 1, 0).getDate()
                        }
                        readonly property int dayNum: index - firstDow + 1
                        readonly property bool inMonth: dayNum >= 1 && dayNum <= daysInMonth
                        readonly property bool isToday: {
                            if (!inMonth) return false
                            var n = new Date()
                            return calendarFlyout.monthOffset === 0
                                && n.getDate() === dayNum
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            width: 20
                            height: 18
                            color: parent.isToday ? Theme.text : "transparent"
                            visible: parent.inMonth

                            Text {
                                anchors.centerIn: parent
                                text: parent.parent.dayNum
                                color: parent.parent.isToday ? Theme.base : Theme.text
                                font.family: Theme.fontText
                                font.pixelSize: Theme.fontBody
                                font.bold: parent.parent.isToday
                            }
                        }
                    }
                }
            }
        }

        // brightness
        FlyoutPanel {
            scope: screenScope
            flyout: "brightness"
            menuWidth: 220

            FlyoutHeading { text: "BRIGHTNESS  " + bar.brightness + "%" }

            Slider {
                width: parent.width
                value: bar.brightness
                onMoved: v => bar.setBrightness(v)
            }
        }

        // volume
        FlyoutPanel {
            scope: screenScope
            flyout: "volume"
            menuWidth: 220

            FlyoutHeading {
                text: "VOLUME  " + (bar.volumeMuted() ? "MUTED" : bar.volumePercent() + "%")
            }

            Slider {
                width: parent.width
                value: bar.volumePercent()
                onMoved: v => bar.setVolume(v)
            }

            FlyoutRow {
                label: bar.volumeMuted() ? "Unmute" : "Mute"
                onActivated: {
                    if (bar.sink && bar.sink.ready && bar.sink.audio)
                        bar.sink.audio.muted = !bar.sink.audio.muted
                }
            }

            FlyoutRow {
                label: "Sound settings"
                onActivated: {
                    screenScope.openFlyout = ""
                    Quickshell.execDetached(["pavucontrol"])
                }
            }
        }

        // network (iwd)
        FlyoutPanel {
            id: netFlyout
            scope: screenScope
            flyout: "network"
            menuWidth: 280

            // "" when browsing the list; an SSID while its passphrase is
            // being typed. Only then does the panel take keyboard focus.
            property string pendingSsid: ""
            wantsKeyboard: pendingSsid !== ""
            onOpenChanged: if (!open) { pendingSsid = ""; pass.text = "" }

            function connectTo(ssid, passphrase) {
                // --passphrase rather than iwd's interactive prompt, which
                // needs a tty. It does put the passphrase in this process's
                // argv for the lifetime of the call, where anything running
                // as this user could read it out of ps.
                var cmd = ["iwctl"]
                if (passphrase !== "") cmd.push("--passphrase", passphrase)
                cmd.push("station", bar.netDevice, "connect", ssid)
                netConnect.command = cmd
                netConnect.running = true
                pendingSsid = ""
                pass.text = ""
                screenScope.openFlyout = ""
            }

            FlyoutHeading {
                text: netFlyout.pendingSsid !== ""
                    ? "PASSPHRASE"
                    : (bar.netSsid !== "" ? "NETWORK  " + bar.netSsid : "NETWORK  offline")
            }

            // --- passphrase prompt ---
            FlyoutRow {
                visible: netFlyout.pendingSsid !== ""
                label: netFlyout.pendingSsid
                enabled: false
            }

            FlyoutInput {
                id: pass
                visible: netFlyout.pendingSsid !== ""
                placeholder: "passphrase"
                onAccepted: netFlyout.connectTo(netFlyout.pendingSsid, text)
            }

            FlyoutRow {
                visible: netFlyout.pendingSsid !== ""
                label: "Connect"
                trailing: ""
                onActivated: netFlyout.connectTo(netFlyout.pendingSsid, pass.text)
            }

            FlyoutRow {
                visible: netFlyout.pendingSsid !== ""
                label: "Cancel"
                onActivated: { netFlyout.pendingSsid = ""; pass.text = "" }
            }

            // --- network list ---
            FlyoutRow {
                visible: netFlyout.pendingSsid === ""
                label: "Rescan"
                trailing: bar.netDevice
                onActivated: netScan.running = true
            }

            Repeater {
                // iwctl already orders by signal, so the cap keeps the ten
                // strongest rather than an arbitrary ten
                model: netFlyout.pendingSsid === "" ? bar.netList.slice(0, 10) : []

                FlyoutRow {
                    required property var modelData
                    label: modelData.ssid
                    // "key" marks the ones that will ask for a passphrase
                    // rather than connecting straight away
                    trailing: {
                        if (modelData.connected) return "\uf00c"
                        if (!modelData.known && modelData.security !== "open") return "key"
                        return "\u2022".repeat(Math.max(1, modelData.bars))
                    }
                    highlighted: modelData.connected
                    onActivated: {
                        if (modelData.connected) return
                        // a known or open network needs no passphrase: iwd
                        // either has the key already or there is none
                        if (modelData.known || modelData.security === "open") {
                            netFlyout.connectTo(modelData.ssid, "")
                        } else {
                            netFlyout.pendingSsid = modelData.ssid
                            pass.text = ""
                            pass.forceFocus()
                        }
                    }
                }
            }

            FlyoutRow {
                label: bar.netDevice === "" ? "No wifi device" : "No networks found"
                enabled: false
                visible: netFlyout.pendingSsid === "" && bar.netList.length === 0
            }

            FlyoutRow {
                label: "+ " + (bar.netList.length - 10) + " weaker"
                enabled: false
                visible: netFlyout.pendingSsid === "" && bar.netList.length > 10
            }
        }

        // bluetooth
        FlyoutPanel {
            id: btFlyout
            scope: screenScope
            flyout: "bluetooth"
            menuWidth: 280

            // Discovery is started only by the Scan row, never by opening
            // the panel: it keeps the radio busy and churns the list, and
            // most visits here are to connect something already paired.
            // Closing still stops it, so a scan can't be left running.
            onOpenChanged: {
                if (open) return
                var a = Bluetooth.defaultAdapter
                if (a && a.enabled) a.discovering = false
            }

            FlyoutHeading { text: "BLUETOOTH" }

            FlyoutRow {
                readonly property var adapter: Bluetooth.defaultAdapter
                label: (adapter && adapter.enabled) ? "Powered on" : "Powered off"
                trailing: (adapter && adapter.enabled) ? "" : ""
                onActivated: {
                    var a = Bluetooth.defaultAdapter
                    if (a) a.enabled = !a.enabled
                }
            }

            FlyoutRow {
                readonly property var adapter: Bluetooth.defaultAdapter
                // discovery is meaningless with the radio off, and bluez
                // errors rather than ignoring the request
                visible: adapter && adapter.enabled
                label: (adapter && adapter.discovering) ? "Scanning" : "Scan"
                trailing: (adapter && adapter.discovering) ? "stop" : adapter ? adapter.adapterId : ""
                onActivated: {
                    var a = Bluetooth.defaultAdapter
                    if (a && a.enabled) a.discovering = !a.discovering
                }
            }

            // BlueZ hands back everything the radio hears -- here ~27
            // devices, of which only 5 have a name. The rest are BLE privacy
            // advertisements (phones, watches, tags) broadcasting a rotating
            // random address and nothing else. They can't be paired with and
            // they bury the device you're looking for.
            function btKeep(d) {
                if (d.paired || d.connected) return true
                if (d.deviceName !== "") return true
                // nameless hardware BlueZ could still classify: a headset
                // that hasn't answered a name request yet still reports a
                // device class, where a privacy beacon reports nothing
                return d.icon !== ""
            }

            function btAll() {
                var a = Bluetooth.defaultAdapter
                return (a && a.devices) ? a.devices.values : []
            }

            function btByName(list) {
                return list.sort(function(x, y) {
                    if (x.connected !== y.connected) return x.connected ? -1 : 1
                    return (x.deviceName || "").localeCompare(y.deviceName || "")
                })
            }

            // things you've paired before, whether or not they're in range
            function btSaved() {
                return btByName(btAll().filter(function(d) {
                    return d.paired || d.connected
                }))
            }

            // everything else the scan turned up
            function btNearby() {
                return btByName(btAll().filter(function(d) {
                    return !d.paired && !d.connected && btFlyout.btKeep(d)
                }))
            }

            function btHiddenCount() {
                return btAll().filter(function(d) {
                    return !d.paired && !d.connected && !btFlyout.btKeep(d)
                }).length
            }

            FlyoutHeading {
                text: "SAVED"
                visible: btFlyout.btSaved().length > 0
            }

            Repeater {
                model: btFlyout.btSaved()
                BtDeviceRow { required property var modelData; device: modelData }
            }

            FlyoutHeading {
                text: "NEARBY"
                visible: btFlyout.btNearby().length > 0
            }

            Repeater {
                model: btFlyout.btNearby().slice(0, 10)
                BtDeviceRow { required property var modelData; device: modelData }
            }

            FlyoutRow {
                label: "No devices"
                enabled: false
                visible: btFlyout.btSaved().length === 0 && btFlyout.btNearby().length === 0
            }

            FlyoutRow {
                label: "+ " + btFlyout.btHiddenCount() + " unnamed"
                enabled: false
                visible: btFlyout.btHiddenCount() > 0
            }
        }

        // battery
        FlyoutPanel {
            id: batteryFlyout
            scope: screenScope
            flyout: "battery"
            menuWidth: 240
            // last module in the bar -- run it into the right corner
            edgeMargin: 0

            function fmtSeconds(s) {
                if (!s || s <= 0) return "--"
                var h = Math.floor(s / 3600)
                var m = Math.floor((s % 3600) / 60)
                return h > 0 ? h + "h " + m + "m" : m + "m"
            }

            FlyoutHeading {
                text: "BATTERY  " + (bar.hasBattery ? bar.batteryPercent() + "%" : "--")
            }

            FlyoutRow {
                label: UPower.onBattery ? "Discharging" : "Charging"
                trailing: UPower.onBattery
                    ? batteryFlyout.fmtSeconds(bar.batt ? bar.batt.timeToEmpty : 0) + " left"
                    : batteryFlyout.fmtSeconds(bar.batt ? bar.batt.timeToFull : 0) + " to full"
                enabled: false
            }

            FlyoutRow {
                label: "Draw"
                trailing: bar.batt ? Math.abs(bar.batt.changeRate).toFixed(1) + " W" : "--"
                enabled: false
            }

            FlyoutRow {
                label: "Health"
                trailing: (bar.batt && bar.batt.healthSupported)
                    ? Math.round(bar.batt.healthPercentage) + "%"
                    : "n/a"
                enabled: false
            }

            FlyoutHeading { text: "POWER PROFILE" }

            FlyoutRow {
                visible: PpdProfile.profile === ""
                label: "power-profiles-daemon not answering"
                enabled: false
            }

            Repeater {
                model: [
                    { name: "power-saver", label: "Power Saver" },
                    { name: "balanced",    label: "Balanced" },
                    { name: "performance", label: "Performance" },
                ]

                FlyoutRow {
                    required property var modelData
                    visible: PpdProfile.profile !== ""
                    label: modelData.label
                    highlighted: PpdProfile.profile === modelData.name
                    trailing: highlighted ? "" : ""
                    onActivated: PpdProfile.set(modelData.name)
                }
            }

        }

        // tray menu: the app's own menu, drawn as flyout rows so it matches
        // everything else rather than popping a native Qt menu. Submenus
        // drill down in place, like the control centre.
        FlyoutPanel {
            id: trayMenu
            scope: screenScope
            flyout: "traymenu"
            menuWidth: 240

            property var item: null
            // submenu handles, innermost last
            property var stack: []
            onOpenChanged: if (!open) stack = []

            QsMenuOpener {
                id: trayOpener
                menu: trayMenu.stack.length > 0 ? trayMenu.stack[trayMenu.stack.length - 1]
                    : (trayMenu.item ? trayMenu.item.menu : null)
            }

            FlyoutHeading {
                text: trayMenu.item ? (trayMenu.item.title || trayMenu.item.id || "MENU").toUpperCase() : "MENU"
            }

            FlyoutRow {
                visible: trayMenu.stack.length > 0
                label: "󰅁  Back"
                onActivated: trayMenu.stack = trayMenu.stack.slice(0, -1)
            }

            Repeater {
                model: trayMenu.open ? trayOpener.children.values : []

                Item {
                    id: entryRow
                    required property var modelData
                    width: parent ? parent.width : 0
                    implicitHeight: modelData.isSeparator ? divider.implicitHeight : row.implicitHeight
                    height: implicitHeight

                    FlyoutDivider {
                        id: divider
                        visible: entryRow.modelData.isSeparator
                    }

                    FlyoutRow {
                        id: row
                        visible: !entryRow.modelData.isSeparator
                        label: entryRow.modelData.text.replace(/_/g, "")
                        enabled: entryRow.modelData.enabled
                        // checkState 2 = checked, for toggle and radio entries
                        highlighted: entryRow.modelData.checkState === 2
                        trailing: entryRow.modelData.hasChildren ? "󰅂" : ""
                        onActivated: {
                            if (entryRow.modelData.hasChildren) {
                                trayMenu.stack = trayMenu.stack.concat([entryRow.modelData])
                            } else {
                                entryRow.modelData.triggered()
                                screenScope.openFlyout = ""
                            }
                        }
                    }
                }
            }
        }

        // media
        FlyoutPanel {
            id: mediaFlyout
            scope: screenScope
            flyout: "media"
            menuWidth: 280

            readonly property var player: Media.player

            // MPRIS position isn't pushed while playing, only on seeks and
            // track changes, so it's nudged each second while this is open
            Timer {
                interval: 1000
                repeat: true
                running: mediaFlyout.open && mediaFlyout.player && mediaFlyout.player.isPlaying
                onTriggered: if (mediaFlyout.player) mediaFlyout.player.positionChanged()
            }

            FlyoutHeading {
                text: mediaFlyout.player ? mediaFlyout.player.identity.toUpperCase() : "MEDIA"
            }

            Item {
                width: parent.width
                height: 64

                Rectangle {
                    id: artFrame
                    width: 64
                    height: 64
                    radius: Theme.radiusInner
                    color: Theme.base
                    border.width: 1
                    border.color: Theme.border
                    clip: true

                    Image {
                        id: art
                        anchors.fill: parent
                        anchors.margins: 1
                        source: mediaFlyout.player ? mediaFlyout.player.trackArtUrl : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: status === Image.Ready
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: art.status !== Image.Ready
                        text: "󰝚"
                        color: Theme.muted
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fs(26)
                    }
                }

                Column {
                    anchors.left: artFrame.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    Text {
                        width: parent.width
                        text: mediaFlyout.player ? (mediaFlyout.player.trackTitle || "Nothing playing") : ""
                        elide: Text.ElideRight
                        color: Theme.bright
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontBody
                        font.bold: true
                    }
                    Text {
                        width: parent.width
                        text: mediaFlyout.player ? mediaFlyout.player.trackArtist : ""
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontBody
                    }
                    Text {
                        width: parent.width
                        visible: text !== ""
                        text: mediaFlyout.player ? mediaFlyout.player.trackAlbum : ""
                        elide: Text.ElideRight
                        color: Theme.subtext
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontSmall
                    }
                }
            }

            // progress, and click-to-seek where the player allows it
            Item {
                width: parent.width
                height: 24
                visible: mediaFlyout.player && mediaFlyout.player.lengthSupported && mediaFlyout.player.length > 0

                readonly property real frac: mediaFlyout.player && mediaFlyout.player.length > 0
                    ? Math.max(0, Math.min(1, mediaFlyout.player.position / mediaFlyout.player.length)) : 0

                Rectangle {
                    id: track
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: 4
                    height: 6
                    radius: 3
                    color: Theme.base
                    border.width: 1
                    border.color: Theme.surface

                    Rectangle {
                        height: parent.height
                        radius: 3
                        width: Math.max(parent.frac > 0 ? height : 0, parent.width * parent.parent.frac)
                        color: Theme.text
                    }

                    MouseArea {
                        anchors.fill: parent
                        anchors.topMargin: -6
                        anchors.bottomMargin: -6
                        enabled: mediaFlyout.player && mediaFlyout.player.canSeek
                        cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: mouse => mediaFlyout.player.position =
                            mediaFlyout.player.length * Math.max(0, Math.min(1, mouse.x / width))
                    }
                }

                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    text: mediaFlyout.player ? Media.fmtTime(mediaFlyout.player.position) : ""
                    color: Theme.subtext
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontSmall
                }
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: mediaFlyout.player ? Media.fmtTime(mediaFlyout.player.length) : ""
                    color: Theme.subtext
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontSmall
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8

                FlyoutChip {
                    glyph: true
                    text: "󰒮"
                    enabled: mediaFlyout.player && mediaFlyout.player.canGoPrevious
                    onClicked: mediaFlyout.player.previous()
                }
                FlyoutChip {
                    glyph: true
                    text: mediaFlyout.player && mediaFlyout.player.isPlaying ? "󰏤" : "󰐊"
                    enabled: mediaFlyout.player && mediaFlyout.player.canTogglePlaying
                    onClicked: mediaFlyout.player.togglePlaying()
                }
                FlyoutChip {
                    glyph: true
                    text: "󰒭"
                    enabled: mediaFlyout.player && mediaFlyout.player.canGoNext
                    onClicked: mediaFlyout.player.next()
                }
            }

            // more than one player: pick which the module follows
            FlyoutHeading {
                visible: Media.players.length > 1
                text: "PLAYERS"
            }

            Repeater {
                model: Media.players.length > 1 ? Media.players : []

                FlyoutRow {
                    required property var modelData
                    label: modelData.identity + (modelData.trackTitle ? "  ·  " + modelData.trackTitle : "")
                    highlighted: modelData === Media.player
                    trailing: modelData.isPlaying ? "󰐊" : ""
                    onActivated: Media.lastPlaying = modelData
                }
            }
        }

        // weather
        FlyoutPanel {
            id: weatherFlyout
            scope: screenScope
            flyout: "weather"
            menuWidth: 250

            FlyoutHeading { text: Weather.area !== "" ? Weather.area.toUpperCase() : "WEATHER" }

            Item {
                width: parent.width
                height: 46

                Text {
                    id: bigIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.iconFor(Weather.code, Weather.isNight)
                    color: Theme.bright
                    font.family: Theme.fontIcon
                    font.pixelSize: Theme.fs(34)
                }

                Column {
                    anchors.left: bigIcon.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        text: Weather.temp(Weather.tempF, Weather.tempC)
                        color: Theme.bright
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fs(22)
                        font.bold: true
                    }
                    Text {
                        text: Weather.condition
                        color: Theme.text
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontSmall
                    }
                }
            }

            FlyoutRow { label: "Feels like"; trailing: Weather.temp(Weather.feelsF, Weather.feelsC); enabled: false }
            FlyoutRow { label: "Humidity";   trailing: Weather.humidity + "%"; enabled: false }
            FlyoutRow { label: "Wind";       trailing: Weather.wind; enabled: false }

            FlyoutHeading { text: "FORECAST" }

            Repeater {
                model: Weather.forecast

                Item {
                    required property var modelData
                    required property int index
                    width: parent ? parent.width : 0
                    height: 24

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 56
                        text: index === 0 ? "Today"
                            : Qt.formatDate(new Date(modelData.date + "T12:00:00"), "ddd")
                        color: Theme.text
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontBody
                    }
                    Text {
                        x: 60
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.iconFor(modelData.code, false)
                        color: Theme.text
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontIconSize
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: Weather.temp(modelData.hiF, modelData.hiC) + "  /  " + Weather.temp(modelData.loF, modelData.loC)
                        color: Theme.bright
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontBody
                    }
                }
            }

            FlyoutDivider {}

            Item {
                width: parent.width
                height: 22

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: Weather.failed ? "Last update failed"
                        : Weather.updated ? "Updated " + Qt.formatTime(Weather.updated, "HH:mm") : ""
                    color: Weather.failed ? Theme.alert : Theme.subtext
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontSmall
                }

                Row {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    FlyoutChip { text: "°F"; selected: !Weather.metric; onClicked: Settings.setWeatherUnits("F") }
                    FlyoutChip { text: "°C"; selected: Weather.metric;  onClicked: Settings.setWeatherUnits("C") }
                    FlyoutChip { glyph: true; text: "󰑐"; onClicked: Weather.refresh() }
                }
            }
        }

        // privacy
        FlyoutPanel {
            id: privacyFlyout
            scope: screenScope
            flyout: "privacy"
            menuWidth: 240

            FlyoutHeading { text: "IN USE" }

            Repeater {
                model: [
                    { icon: "󰍬", kind: "Microphone", apps: Privacy.state.mic },
                    { icon: "󰄀", kind: "Camera",     apps: Privacy.state.camera },
                    { icon: "󰍹", kind: "Screen",     apps: Privacy.state.screen },
                ].filter(k => k.apps.length > 0)

                FlyoutAction {
                    required property var modelData
                    checkable: false
                    enabled: false
                    icon: modelData.icon
                    label: modelData.kind
                    // unique names: a browser opens one stream per tab
                    status: modelData.apps.filter((a, i, all) => all.indexOf(a) === i).join(", ")
                }
            }
        }

        // failed units
        FlyoutPanel {
            id: failedFlyout
            scope: screenScope
            flyout: "failed"
            menuWidth: 300

            FlyoutHeading { text: "FAILED SERVICES" }

            FlyoutRow {
                visible: FailedUnits.count === 0
                label: "Nothing has failed"
                enabled: false
            }

            Repeater {
                model: FailedUnits.units

                Item {
                    required property var modelData
                    width: parent ? parent.width : 0
                    height: 46

                    Text {
                        id: unitName
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.topMargin: 2
                        text: modelData.name
                        elide: Text.ElideMiddle
                        color: Theme.bright
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontBody
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        text: modelData.user ? "user" : "system"
                        color: Theme.subtext
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontSmall
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 1
                        spacing: 4
                        FlyoutChip { text: "Log";     onClicked: { FailedUnits.showLog(modelData); screenScope.openFlyout = "" } }
                        FlyoutChip { text: "Restart"; onClicked: FailedUnits.restart(modelData) }
                        FlyoutChip { text: "Clear";   onClicked: FailedUnits.clear(modelData) }
                    }
                }
            }
        }

        // updates
        FlyoutPanel {
            id: updatesFlyout
            scope: screenScope
            flyout: "updates"
            menuWidth: 300

            FlyoutHeading {
                text: "UPDATES  " + Updates.count
                    + (Updates.aurCount > 0 ? "  (" + Updates.aurCount + " AUR)" : "")
            }

            ListView {
                id: updList
                width: parent.width
                height: Math.min(contentHeight, 12 * 22)
                clip: true
                interactive: contentHeight > height
                boundsBehavior: Flickable.StopAtBounds
                model: Updates.packages

                delegate: Item {
                    required property var modelData
                    width: updList.width
                    height: 22

                    Text {
                        anchors.left: parent.left
                        anchors.right: ver.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name + (modelData.aur ? "  ·aur" : "")
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontBody
                    }
                    Text {
                        id: ver
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 150)
                        horizontalAlignment: Text.AlignRight
                        text: modelData.to
                        elide: Text.ElideLeft
                        color: Theme.subtext
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontSmall
                    }
                }
            }

            FlyoutDivider {}

            FlyoutRow {
                label: "Update now"
                trailing: "󰚰"
                onActivated: {
                    Updates.update()
                    screenScope.openFlyout = ""
                }
            }

            FlyoutRow {
                label: Updates.checking ? "Checking..." : "Check again"
                trailing: Updates.lastChecked ? Qt.formatTime(Updates.lastChecked, "HH:mm") : ""
                enabled: !Updates.checking
                onActivated: Updates.refresh()
            }
        }

        // control centre
        FlyoutPanel {
            id: controlCentre
            scope: screenScope
            flyout: "controlcentre"
            menuWidth: 230
            // first module in the bar -- run it into the left corner
            edgeMargin: 0

            // Drill-down rather than nested pop-out panels: "" is the root
            // list and anything else is a submenu drawn in the same box. A
            // second floating panel would have to track the first one's
            // geometry and its own click-off, for a menu this size.
            property string page: ""
            // always reopen at the top level
            onOpenChanged: if (!open) page = ""
            keyboardExclusive: open && page === "apps"

            property string appQuery: ""
            // Re-read the saved layout each time the page opens, so the
            // lists never show an order from before a reset or a hand edit.
            onPageChanged: if (page === "widgets") {
                widgetsList.refill()
            } else if (page === "apps") {
                appQuery = ""
                appSearch.text = ""
                appView.currentIndex = 0
                // after the field has become visible, or focus is refused
                Qt.callLater(appSearch.forceFocus)
            }

            // Desktop entry ids kept out of the list: system tools that
            // arrived as dependencies of something else and aren't ever
            // launched by hand. Ids rather than names, so a translation or a
            // package renaming its Name= line doesn't let one back in.
            readonly property var hiddenApps: [
                "avahi-discover", "bssh", "bvnc",   // avahi
                "lstopo",                           // hwloc
                "qv4l2", "qvidcap",                 // v4l-utils
                "xfce4-about",                      // xfce4-about
                "jconsole-java25-openjdk",          // jdk
                "jshell-java25-openjdk",
                "thunar-settings",                  // thunar extras
                "thunar-volman-settings",
                "thunar-bulk-rename",
            ]
            readonly property var pageTitles: ({
                "power": "POWER",
                "appearance": "APPEARANCE",
                "quick": "QUICK ACTIONS",
                "apps": "APPLICATIONS",
                "widgets": "BAR WIDGETS"
            })

            // Every launchable desktop entry, A-Z. Case-insensitive, or
            // lowercase names ("htop", "nvim") would all sort after Z.
            //
            // With a query, names that *start* with it come first, then any
            // other match, each group still A-Z. genericName is searched too,
            // so "browser" finds Zen and Floorp.
            function appList(query) {
                var all = DesktopEntries.applications.values
                var q = (query || "").trim().toLowerCase()
                var starts = [], rest = []
                for (var i = 0; i < all.length; i++) {
                    var e = all[i]
                    if (e.noDisplay || hiddenApps.indexOf(e.id) !== -1) continue
                    var name = e.name.toLowerCase()
                    if (q === "") { rest.push(e); continue }
                    if (name.startsWith(q)) starts.push(e)
                    else if (name.indexOf(q) !== -1
                        || (e.genericName || "").toLowerCase().indexOf(q) !== -1) rest.push(e)
                }
                var byName = (a, b) => a.name.toLowerCase().localeCompare(b.name.toLowerCase())
                starts.sort(byName)
                rest.sort(byName)
                return starts.concat(rest)
            }

            function launch(entry) {
                screenScope.openFlyout = ""
                // execute() runs the Exec line as-is, which for a terminal
                // app (htop, nvim) means a process with no terminal to draw
                // in -- it starts and dies unseen. Those get wrapped.
                if (entry.runInTerminal) {
                    // command is a Qt list, not a JS array: concat() would
                    // push it as one nested element instead of spreading it
                    var cmd = ["alacritty", "-e"]
                    for (var i = 0; i < entry.command.length; i++) cmd.push(entry.command[i])
                    Quickshell.execDetached(cmd)
                } else
                    entry.execute()
            }

            function run(act) {
                screenScope.openFlyout = ""
                if (act === "settings") settingsWindow.open()
                else if (act === "system") system.open()
                else if (act === "keybinds") keybinds.open()
                else if (act === "lock") Quickshell.execDetached(["hyprlock"])
                else if (act === "sleep") Quickshell.execDetached(["systemctl", "suspend"])
                else if (act === "logout") Hyprland.dispatch("hl.dsp.exit()")
                else if (act === "reboot") Quickshell.execDetached(["systemctl", "reboot"])
                else if (act === "poweroff") Quickshell.execDetached(["systemctl", "poweroff"])
                // The pause lets the flyout's surface unmap first. slurp and
                // hyprpicker both draw on the overlay layer too, and without
                // it the menu is still on screen for their first frame --
                // in the picker's case, close enough to pick its own pixels.
                else if (act === "screenshot")
                    Quickshell.execDetached(["sh", "-c", "sleep 0.2; ~/.config/hypr/screenshot.sh"])
                else if (act === "colourpick")
                    Quickshell.execDetached(["sh", "-c", "sleep 0.2; ~/.config/hypr/colour-pick.sh"])
            }

            FlyoutHeading {
                text: controlCentre.page === ""
                    ? "CONTROL CENTRE"
                    : (controlCentre.pageTitles[controlCentre.page] || "")
            }

            FlyoutRow {
                visible: controlCentre.page !== ""
                label: "󰅁  Back"
                onActivated: controlCentre.page = ""
            }

            // root, first group: the things that open a submenu
            Repeater {
                model: controlCentre.page === "" ? [
                    { label: "Applications",   sub: "apps" },
                    { label: "Power",          sub: "power" },
                    { label: "Bar Widgets",    sub: "widgets" },
                    { label: "Quick Actions",  sub: "quick" },
                    { label: "Appearance",     sub: "appearance" },
                ] : []

                FlyoutRow {
                    required property var modelData
                    label: modelData.label
                    trailing: "󰅂"
                    onActivated: controlCentre.page = modelData.sub
                }
            }

            FlyoutDivider {
                visible: controlCentre.page === ""
            }

            // root, second group: the leaf entries
            Repeater {
                model: controlCentre.page === "" ? [
                    { label: "Settings",   act: "settings" },
                    { label: "System",     act: "system" },
                    { label: "Keybinds",   act: "keybinds" },
                ] : []

                FlyoutRow {
                    required property var modelData
                    label: modelData.label
                    onActivated: controlCentre.run(modelData.act)
                }
            }

            // --- Applications -----------------------------------------
            // A list rather than rows in the column: at ~30 apps the panel
            // would run most of the way down the screen, so it scrolls
            // inside a fixed-height window instead.

            FlyoutInput {
                id: appSearch
                visible: controlCentre.page === "apps"
                placeholder: "Search"
                echoPassword: false
                onTextChanged: {
                    controlCentre.appQuery = text
                    appView.currentIndex = 0
                }
                // Enter launches whatever is highlighted -- the top match
                // until the arrows move it
                onAccepted: if (appView.count > 0)
                    controlCentre.launch(appView.model[appView.currentIndex])
                onDownPressed: if (appView.currentIndex < appView.count - 1) appView.currentIndex++
                onUpPressed: if (appView.currentIndex > 0) appView.currentIndex--
                onEscapePressed: screenScope.openFlyout = ""
            }

            FlyoutRow {
                visible: controlCentre.page === "apps" && appView.count === 0
                label: "No matches"
                enabled: false
            }

            ListView {
                id: appView
                visible: controlCentre.page === "apps"
                width: parent.width
                // 14 rows, or fewer if there are fewer apps
                height: visible ? Math.min(contentHeight, 14 * 28) : 0
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: visible ? controlCentre.appList(controlCentre.appQuery) : []
                // keeps the arrow-key selection scrolled into view
                onCurrentIndexChanged: positionViewAtIndex(currentIndex, ListView.Contain)
                // back to the top each time the page opens
                onVisibleChanged: if (visible) positionViewAtBeginning()

                delegate: Item {
                    id: appRow
                    required property var modelData
                    required property int index
                    width: appView.width
                    height: 26

                    Rectangle {
                        anchors.fill: parent
                        radius: Theme.radiusInner
                        color: appRow.ListView.isCurrentItem ? Theme.overlay : "transparent"
                    }

                    IconImage {
                        id: appIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 2
                        anchors.verticalCenter: parent.verticalCenter
                        implicitSize: 18
                        source: Quickshell.iconPath(appRow.modelData.icon, true)
                    }

                    Text {
                        anchors.left: appIcon.right
                        anchors.leftMargin: 9
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: appRow.modelData.name
                        elide: Text.ElideRight
                        color: appRow.ListView.isCurrentItem ? Theme.bright : Theme.text
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontBody
                    }

                    MouseArea {
                        id: appMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        // one highlight shared by mouse and keys: hovering
                        // moves the selection rather than drawing a second one
                        onContainsMouseChanged: if (containsMouse) appView.currentIndex = appRow.index
                        onClicked: controlCentre.launch(appRow.modelData)
                    }
                }
            }

            // --- Bar Widgets ------------------------------------------

            readonly property var widgetMeta: ({
                controlcentre: { label: "Control Centre", icon: "󰣇" },
                workspaces:    { label: "Workspaces",     icon: "󰇘" },
                overview:      { label: "Window Overview", icon: "󰕰" },
                windows:       { label: "Open Windows",   icon: "󰀻" },
                clock:         { label: "Clock",          icon: "󰅐" },
                bluetooth:     { label: "Bluetooth",      icon: "󰂯" },
                network:       { label: "Network",        icon: "󰤨" },
                volume:        { label: "Volume",         icon: "󰕾" },
                brightness:    { label: "Brightness",     icon: "󰃠" },
                battery:       { label: "Battery",        icon: "󰁹" },
                tray:          { label: "System Tray",    icon: "󰀻" },
                media:         { label: "Media Player",   icon: "󰝚" },
                visualizer:    { label: "Audio Visualizer", icon: "󰺢" },
                weather:       { label: "Weather",        icon: "󰖐" },
                notifications: { label: "Notifications",  icon: "󰂚" },
                privacy:       { label: "Privacy",        icon: "󰍬" },
                failed:        { label: "Failed Services", icon: "󰀦" },
                updates:       { label: "Updates",        icon: "󰚰" },
            })

            Column {
                visible: controlCentre.page === "widgets"
                width: parent.width
                spacing: 6

                BarWidgetList {
                    id: widgetsList
                    meta: controlCentre.widgetMeta
                }

                FlyoutDivider {}

                FlyoutRow {
                    label: "Reset to Defaults"
                    enabled: !Settings.widgetsDefault
                    onActivated: {
                        Settings.resetWidgets()
                        widgetsList.refill()
                    }
                }
            }

            // --- Quick Actions ----------------------------------------
            // Toggles stay open after a click, so you can flip several in a
            // row and watch each switch settle. The two momentary actions
            // close the menu, since both need the screen clear.

            Column {
                visible: controlCentre.page === "quick"
                width: parent.width
                spacing: 6

                FlyoutAction {
                    icon: bar.netPowered ? "󰖩" : "󰖪"
                    label: "Wi-Fi"
                    status: bar.netDevice === "" ? "No wifi device"
                        : !bar.netPowered ? "Off"
                        : (bar.netSsid !== "" ? bar.netSsid : "Not connected")
                    enabled: bar.netDevice !== ""
                    checked: bar.netPowered
                    onActivated: bar.setWifiPowered(!bar.netPowered)
                }

                FlyoutAction {
                    readonly property var adapter: Bluetooth.defaultAdapter
                    icon: checked ? "󰂯" : "󰂲"
                    label: "Bluetooth"
                    status: !adapter ? "No adapter"
                        : !adapter.enabled ? "Off"
                        : (bar.btConnectedName() !== "" ? bar.btConnectedName() : "No device connected")
                    enabled: adapter !== null
                    checked: adapter ? adapter.enabled : false
                    onActivated: if (adapter) adapter.enabled = !adapter.enabled
                }

                FlyoutAction {
                    icon: bar.volumeMuted() ? "󰖁" : "󰕾"
                    label: "Mute"
                    status: bar.volumeMuted() ? "Muted" : bar.volumePercent() + "%"
                    enabled: bar.sink && bar.sink.ready
                    checked: bar.volumeMuted()
                    onActivated: if (bar.sink && bar.sink.audio) bar.sink.audio.muted = !bar.sink.audio.muted
                }

                FlyoutAction {
                    icon: root.keepAwake ? "󰅶" : "󰾪"
                    label: "Keep Awake"
                    checked: root.keepAwake
                    onActivated: root.keepAwake = !root.keepAwake
                }

                FlyoutAction {
                    icon: root.nightLight ? "󰖔" : "󰖙"
                    label: "Night Light"
                    status: !root.hasHyprsunset ? "hyprsunset not installed" : ""
                    enabled: root.hasHyprsunset
                    checked: root.nightLight
                    onActivated: root.nightLight = !root.nightLight
                }

                // Do Not Disturb lives here as well as on the notification
                // module's right-click, because that module hides itself when
                // nothing is unread -- this is the one place it's always reachable.
                FlyoutAction {
                    icon: Notifications.dnd ? "󰂛" : "󰂚"
                    label: "Do Not Disturb"
                    status: !Notifications.available ? "swaync not running" : ""
                    enabled: Notifications.available
                    checked: Notifications.dnd
                    onActivated: Notifications.toggleDnd()
                }

                // Only while it's on: a warmth control for a light that's off
                // is a setting you can't see the effect of.
                FlyoutStepper {
                    visible: root.nightLight
                    label: "Warmth"
                    labelInset: 28
                    valueWidth: 44
                    suffix: "K"
                    value: Settings.nightLightKelvin
                    minimum: Settings.limits.nightLightKelvin.min
                    maximum: Settings.limits.nightLightKelvin.max
                    // minus is warmer, which is the way the kelvin number goes
                    // anyway, so the buttons need no inversion
                    onStepped: d => Settings.step("nightLightKelvin", d * 250)
                }

                FlyoutDivider {}

                FlyoutAction {
                    checkable: false
                    icon: "󰹑"
                    label: "Screenshot Region"
                    onActivated: controlCentre.run("screenshot")
                }

                FlyoutAction {
                    checkable: false
                    icon: "󰈊"
                    label: "Colour Picker"
                    onActivated: controlCentre.run("colourpick")
                }
            }

            // --- Appearance -------------------------------------------
            // One Column per page, so its rows share a single visibility
            // switch.

            Column {
                id: appearancePage
                visible: controlCentre.page === "appearance"
                width: parent.width
                spacing: 6

                function label(v) { return Settings.choiceLabels[v] || v }

                FlyoutHeading { text: "WALLPAPER" }

                // click-through preview: the fastest way to flick through
                ClippingRectangle {
                    width: parent.width
                    height: Math.round(width * 9 / 16)
                    radius: Theme.radiusInner
                    color: Theme.base
                    border.width: 1
                    border.color: previewMouse.containsMouse ? Theme.subtext : Theme.border

                    Image {
                        anchors.fill: parent
                        source: Wallpaper.current !== "" ? "file://" + Wallpaper.current : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // decoded at preview size, not the wallpaper's own
                        // 4K, which would hold tens of MB for a thumbnail
                        sourceSize.width: 480
                    }

                    MouseArea {
                        id: previewMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Wallpaper.step(1)
                    }
                }

                Item {
                    width: parent.width
                    height: Theme.fs(20)

                    Text {
                        anchors.left: parent.left
                        anchors.right: wpButtons.left
                        anchors.rightMargin: 8
                        anchors.verticalCenter: parent.verticalCenter
                        text: Wallpaper.name !== "" ? Wallpaper.name : "No wallpaper"
                        elide: Text.ElideRight
                        color: Theme.text
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontBody
                    }

                    Row {
                        id: wpButtons
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        FlyoutChip { glyph: true; text: "󰒮"; enabled: Wallpaper.images.length > 1; onClicked: Wallpaper.step(-1) }
                        FlyoutChip { glyph: true; text: "󰒝"; enabled: Wallpaper.images.length > 1; onClicked: Wallpaper.shuffle() }
                        FlyoutChip { glyph: true; text: "󰒭"; enabled: Wallpaper.images.length > 1; onClicked: Wallpaper.step(1) }
                    }
                }

                FlyoutRow {
                    // Random: a different wallpaper every login. Static: the
                    // one showing now, kept until you pick another.
                    label: "At Login"
                    trailingIsValue: true
                    trailing: Settings.wallpaperShuffle ? "Random" : "Static"
                    onActivated: Settings.setWallpaperShuffle(!Settings.wallpaperShuffle)
                }

                FlyoutHeading { text: "COLOURS" }

                FlyoutRow {
                    label: "Palette"
                    trailingIsValue: true
                    trailing: appearancePage.label(Settings.colourMode)
                    onActivated: Settings.cycle("colourMode")
                }

                // only means anything once the colours come from the image
                FlyoutRow {
                    label: "Intensity"
                    trailingIsValue: true
                    visible: Settings.colourMode === "wallpaper"
                    trailing: Wallpaper.generating ? "…" : appearancePage.label(Settings.colourScheme)
                    onActivated: Settings.cycle("colourScheme")
                }

                FlyoutHeading { text: "BAR" }

                FlyoutRow {
                    label: "Position"
                    trailingIsValue: true
                    trailing: Settings.barPosition === "bottom" ? "Bottom" : "Top"
                    onActivated: Settings.set("barPosition",
                        Settings.barPosition === "top" ? "bottom" : "top")
                }

                FlyoutStepper {
                    label: "Height"
                    value: Settings.barHeight
                    minimum: Settings.limits.barHeight.min
                    maximum: Settings.limits.barHeight.max
                    onStepped: d => Settings.step("barHeight", d)
                }

                FlyoutStepper {
                    label: "Module Gap"
                    value: Settings.moduleGap
                    minimum: Settings.limits.moduleGap.min
                    maximum: Settings.limits.moduleGap.max
                    onStepped: d => Settings.step("moduleGap", d)
                }

                FlyoutStepper {
                    label: "Corner Radius"
                    value: Settings.radius
                    minimum: Settings.limits.radius.min
                    maximum: Settings.limits.radius.max
                    onStepped: d => Settings.step("radius", d)
                }

                FlyoutStepper {
                    label: "Opacity"
                    value: Settings.barOpacity
                    minimum: Settings.limits.barOpacity.min
                    maximum: Settings.limits.barOpacity.max
                    suffix: "%"
                    valueWidth: 44
                    onStepped: d => Settings.step("barOpacity", d * 5)
                }

                FlyoutHeading { text: "TEXT & MOTION" }

                FlyoutStepper {
                    label: "Font Size"
                    value: Settings.fontScale
                    minimum: Settings.limits.fontScale.min
                    maximum: Settings.limits.fontScale.max
                    suffix: "%"
                    valueWidth: 44
                    onStepped: d => Settings.step("fontScale", d * 5)
                }

                FlyoutRow {
                    label: "Animations"
                    trailingIsValue: true
                    trailing: appearancePage.label(Settings.animSpeed)
                    onActivated: Settings.cycle("animSpeed")
                }

                FlyoutDivider {}

                FlyoutRow {
                    label: "Reset to Defaults"
                    // greyed out when there is nothing to reset, so the row
                    // doubles as a "this is stock" indicator
                    enabled: !Settings.isDefault
                    onActivated: Settings.reset()
                }
            }

            // --- Power ----------------------------------------------
            Repeater {
                model: controlCentre.page === "power" ? [
                    { label: "Lock",      act: "lock" },
                    { label: "Sleep",     act: "sleep" },
                    { label: "Log Out",   act: "logout" },
                    { label: "Reboot",    act: "reboot" },
                    { label: "Shut Down", act: "poweroff" },
                ] : []

                FlyoutRow {
                    required property var modelData
                    label: modelData.label
                    onActivated: controlCentre.run(modelData.act)
                }
            }
        }

        }
    }
}
