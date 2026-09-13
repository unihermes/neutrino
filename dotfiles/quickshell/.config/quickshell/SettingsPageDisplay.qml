// Neutrino - Quickshell
// ~/.config/quickshell/SettingsPageDisplay.qml
//
// Connected displays, and the hl.monitor() rule each one falls under.
//
// What's listed comes from Hyprland (`hyprctl monitors -j`, as System does);
// what's changed is the rule in hyprland.lua, followed by a reload, which is
// what applies it. A display with a rule of its own has that rule edited. A
// display that only matches the catch-all `output = ""` rule edits the
// catch-all -- which on a laptop is the rule that matters -- and says so,
// with "Own rule" to split it off into one for that output alone.

import Quickshell.Io
import QtQuick
import "HyprTables.js" as HyprTables

SettingsPage {
    id: page

    title: "Display"
    description: "Resolution and scale per display, saved as hl.monitor() rules in hyprland.lua. Hyprland reloads on each change."

    // [{ name, description, width, height, hz, scale, modes: ["WxH@R"] }]
    property var monitors: []
    // hl.monitor() calls, as HyprTables.readMonitors gives them
    property var rules: []

    readonly property var scales: [1, 1.25, 1.5, 1.6, 1.75, 2]

    function reread() {
        luaFile.reload()
        luaFile.waitForJob()
        rules = HyprTables.readMonitors(luaFile.text())
        monitorsProc.running = true
    }

    Component.onCompleted: reread()

    function fieldValue(rule, key, fallback) {
        var f = rule && rule.fields[key]
        return f && f.editable ? f.value : fallback
    }

    function setField(mon, rule, key, value, message) {
        if (!rule) {
            // no rule matches at all: write one for this output
            writer.patch(src => HyprTables.addMonitor(src,
                { output: mon.name, mode: "preferred", position: "auto", scale: 1, [key]: value }), message)
            return
        }
        var index = rule.index
        writer.patch(src => HyprTables.setMonitor(src, index, key, value), message,
            key + " in that hl.monitor() rule isn't a plain value, edit it by hand")
    }

    // copy the catch-all's fields into a rule naming this output
    function ownRule(mon, rule) {
        var fields = { output: mon.name }
        ;["mode", "position", "scale"].forEach(k => fields[k] = fieldValue(rule, k, k === "scale" ? 1 : k === "mode" ? "preferred" : "auto"))
        writer.patch(src => HyprTables.addMonitor(src, fields), mon.name + " has its own rule now")
    }

    Process {
        id: monitorsProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                var data
                try { data = JSON.parse(text) } catch (e) { page.say("hyprctl monitors didn't answer", true); return }
                page.monitors = data.map(m => {
                    var seen = {}
                    // Hyprland lists modes best-first: keep every rate at the
                    // current resolution, and only the first (fastest) of
                    // the others, so a TV's fifteen modes don't bury the page
                    var modes = (m.availableModes || []).map(s => s.replace(/Hz$/, ""))
                        .filter(s => {
                            var res = s.split("@")[0]
                            var k = res === m.width + "x" + m.height ? s : res
                            if (seen[k]) return false
                            seen[k] = true
                            return true
                        })
                    return { name: m.name, description: m.description, width: m.width, height: m.height,
                        hz: m.refreshRate, scale: m.scale, modes: modes }
                })
            }
        }
    }

    FileView {
        id: luaFile
        path: writer.confPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: if (!writer.busy) page.reread()
    }

    HyprLuaWrite {
        id: writer
        visible: false
        onPatched: (ok, message) => {
            page.say(message, !ok)
            page.reread()
        }
    }

    Repeater {
        model: page.monitors

        Column {
            id: mon
            required property var modelData
            readonly property var rule: HyprTables.ruleFor(page.rules, modelData.name)
            readonly property bool catchAll: rule !== null && rule.output === ""
            readonly property var mode: page.fieldValue(rule, "mode", "preferred")
            readonly property real ruleScale: Number(page.fieldValue(rule, "scale", 1))

            width: parent.width
            spacing: 6

            FlyoutHeading { text: mon.modelData.name + " · " + mon.modelData.description.toUpperCase() }

            SettingsField {
                label: "Now"
                hint: mon.rule === null ? "No hl.monitor() rule matches this display"
                    : mon.catchAll ? "Set by the rule for every display (output = \"\")"
                    : "Set by its own rule"

                Row {
                    anchors.right: parent.right
                    spacing: 8

                    Text {
                        height: Theme.fs(20)
                        verticalAlignment: Text.AlignVCenter
                        text: mon.modelData.width + "×" + mon.modelData.height + " @ "
                            + mon.modelData.hz.toFixed(2) + " Hz · scale " + mon.modelData.scale
                        color: Theme.bright
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontBody
                    }
                    FlyoutChip {
                        visible: mon.catchAll
                        text: "Own rule"
                        onClicked: page.ownRule(mon.modelData, mon.rule)
                    }
                }
            }

            SettingsField {
                label: "Scale"
                hint: "1 is native; fractions that don't divide the resolution cleanly get rounded"

                Row {
                    anchors.right: parent.right
                    spacing: 4
                    Repeater {
                        model: page.scales
                        FlyoutChip {
                            required property var modelData
                            text: String(modelData)
                            selected: Math.abs(mon.ruleScale - modelData) < 0.001
                            onClicked: if (!selected)
                                page.setField(mon.modelData, mon.rule, "scale", modelData, mon.modelData.name + " scale set to " + modelData)
                        }
                    }
                }
            }

            SettingsField {
                label: "Mode"
                hint: "preferred is what the display asks for"

                Flow {
                    anchors.right: parent.right
                    width: parent.width
                    spacing: 4

                    Repeater {
                        model: ["preferred", "highres", "highrr"].concat(mon.modelData.modes)
                        FlyoutChip {
                            required property var modelData
                            text: modelData
                            selected: mon.mode === modelData
                            onClicked: if (!selected)
                                page.setField(mon.modelData, mon.rule, "mode", modelData, mon.modelData.name + " mode set to " + modelData)
                        }
                    }
                }
            }

            Item { width: 1; height: 8 }
        }
    }
}
