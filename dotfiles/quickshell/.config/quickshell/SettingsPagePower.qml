// Neutrino - Quickshell
// ~/.config/quickshell/SettingsPagePower.qml
//
// Power profile, and the idle ladder in hypridle.conf.
//
// The profile goes through PpdProfile.qml, as the battery flyout's does,
// and needs no saving -- PPD remembers it.
//
// The ladder is hypridle.conf's listener blocks, each shown by what it does
// (dim, lock, screens off, suspend) and edited in place: only the number on
// its `timeout = N` line changes, the rest of the file is left byte for byte.
// hypridle reads its config once at start, so every write restarts it --
// debounced, so stepping through ten values restarts it once.

import Quickshell
import Quickshell.Io
import QtQuick

SettingsPage {
    id: page

    title: "Power & Idle"
    description: "Power profile, and how long the machine sits idle before each step of hypridle.conf. hypridle restarts to pick up a change."

    readonly property string idlePath: Quickshell.env("HOME") + "/.config/hypr/hypridle.conf"

    // --- power profile -------------------------------------------------------

    // true between this page's own set() and its result, so a change made
    // from the battery flyout meanwhile doesn't report here
    property bool profilePending: false

    Connections {
        target: PpdProfile
        function onSetFinished(ok, error) {
            if (!page.profilePending) return
            page.profilePending = false
            if (!ok) page.say("power-profiles-daemon refused: " + error, true)
            else page.say("Power profile: " + PpdProfile.profile, false)
        }
    }

    // --- idle ladder ---------------------------------------------------------

    // [{ timeout, action, label, line }] -- line is the index of the
    // `timeout = N` line in the file
    property var listeners: []
    property bool idleRunning: false

    function describe(cmd) {
        if (/brightnessctl/.test(cmd)) return "Dim the screen"
        if (/lock-session|hyprlock/.test(cmd)) return "Lock"
        if (/dpms/.test(cmd)) return "Turn screens off"
        if (/suspend|hibernate/.test(cmd)) return /hibernate/.test(cmd) ? "Hibernate" : "Suspend"
        return cmd
    }

    // Blocks are found line by line: `listener {` opens one, `}` closes it,
    // and `#` comments are skipped -- hyprlang has no strings to hide a brace
    // in, so nothing more is needed.
    function parseIdle(text) {
        var lines = text.split("\n")
        var out = [], cur = null
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i].replace(/#.*/, "").trim()
            if (/^listener\s*\{$/.test(l)) { cur = { timeout: -1, action: "", line: -1 }; continue }
            if (!cur) continue
            var m
            if ((m = /^timeout\s*=\s*(\d+)$/.exec(l))) { cur.timeout = Number(m[1]); cur.line = i }
            else if ((m = /^on-timeout\s*=\s*(.*)$/.exec(l))) cur.action = m[1]
            else if (l === "}") {
                if (cur.line >= 0) { cur.label = describe(cur.action); out.push(cur) }
                cur = null
            }
        }
        return out
    }

    function reread() {
        idleFile.reload()
        idleFile.waitForJob()
        var text = idleFile.text()
        if (text === "") { say("Couldn't read " + idlePath, true); listeners = []; return }
        listeners = parseIdle(text)
    }

    function setTimeout_(index, seconds) {
        var copy = listeners.slice()
        copy[index] = Object.assign({}, copy[index], { timeout: seconds })
        listeners = copy
        idleDebounce.restart()
    }

    function writeIdle() {
        idleFile.reload()
        idleFile.waitForJob()
        var lines = idleFile.text().split("\n")
        var fresh = parseIdle(lines.join("\n"))
        if (fresh.length !== listeners.length) {
            say("hypridle.conf changed on disk; nothing written", true)
            reread()
            return
        }
        listeners.forEach((l, i) => {
            var line = fresh[i].line
            lines[line] = lines[line].replace(/(timeout\s*=\s*)\d+/, "$1" + l.timeout)
        })
        idleWrite.command = ["sh", "-c", `
            exec 2>&1
            printf %s "$2" > "$1.new" && cat -- "$1.new" > "$1" && rm -f -- "$1.new" || { echo write; exit; }
            # whichever way it was started -- the unit, or the bare fallback
            # hyprland.lua uses when the unit won't start
            pkill -x hypridle
            systemctl --user reset-failed hypridle.service 2>/dev/null
            systemctl --user restart hypridle.service 2>/dev/null || setsid -f hypridle >/dev/null 2>&1
            echo ok`, "sh", idlePath, lines.join("\n")]
        idleWrite.running = true
    }

    function minutes(s) {
        return s % 60 === 0 ? (s / 60) + " min" : (s / 60).toFixed(1) + " min"
    }

    Component.onCompleted: {
        reread()
        idleCheck.running = true
        PpdProfile.refresh()
    }

    FileView {
        id: idleFile
        path: page.idlePath
        blockLoading: true
        printErrors: false
    }

    Timer {
        id: idleDebounce
        interval: 700
        onTriggered: page.writeIdle()
    }

    Process {
        id: idleWrite
        stdout: StdioCollector {
            onStreamFinished: {
                var ok = text.trim().split("\n").pop() === "ok"
                page.say(ok ? "Saved, hypridle restarted" : "Couldn't write hypridle.conf: " + text.trim(), !ok)
                page.reread()
                idleCheck.running = true
            }
        }
    }

    Process {
        id: idleCheck
        command: ["pgrep", "-x", "hypridle"]
        onExited: code => page.idleRunning = code === 0
    }

    // --- layout --------------------------------------------------------------

    FlyoutHeading { text: "POWER PROFILE" }

    SettingsField {
        label: "Profile"
        hint: PpdProfile.profile === "" ? "power-profiles-daemon isn't answering" : "Performance may not exist on every machine"

        Row {
            anchors.right: parent.right
            spacing: 4
            Repeater {
                model: [{ id: "power-saver", text: "Power saver" }, { id: "balanced", text: "Balanced" },
                    { id: "performance", text: "Performance" }]
                FlyoutChip {
                    required property var modelData
                    text: modelData.text
                    selected: PpdProfile.profile === modelData.id
                    enabled: PpdProfile.profile !== "" && !PpdProfile.busy
                    onClicked: if (!selected) {
                        page.profilePending = true
                        PpdProfile.set(modelData.id)
                    }
                }
            }
        }
    }

    Item { width: 1; height: 6 }
    FlyoutHeading { text: "WHEN IDLE" }

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: page.idleRunning
            ? "Keep Awake in Quick Actions, or a playing video, pauses all of these."
            : "hypridle isn't running, so none of these fire. Changing one starts it."
        color: page.idleRunning ? Theme.subtext : Theme.alert
        font.family: Theme.fontText
        font.pixelSize: Theme.fontSmall
    }

    Repeater {
        model: page.listeners

        SettingsField {
            required property var modelData
            required property int index
            label: modelData.label
            hint: modelData.label === modelData.action ? "" : modelData.action

            FlyoutStepper {
                anchors.right: parent.right
                width: 170
                // in 30-second steps
                value: Math.round(modelData.timeout / 30)
                minimum: 1
                maximum: 240
                valueWidth: 64
                displayValue: page.minutes(modelData.timeout)
                onStepped: delta => page.setTimeout_(index, Math.max(30, (value + delta) * 30))
            }
        }
    }
}
