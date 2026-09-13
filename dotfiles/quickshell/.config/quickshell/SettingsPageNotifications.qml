// Neutrino - Quickshell
// ~/.config/quickshell/SettingsPageNotifications.qml
//
// swaync: Do Not Disturb and the queue, through the Notifications singleton
// the bar module already uses, and a few of config.json's top-level options.
//
// Config edits replace the value on that key's own line and nothing else, so
// the file keeps its layout -- a JSON round trip would reflow every inline
// object in it. `swaync-client -R` then reloads the config in place.

import Quickshell
import Quickshell.Io
import QtQuick

SettingsPage {
    id: page

    title: "Notifications"
    description: "Do Not Disturb, and how long popups stay and where they appear. Saved to swaync's config.json, which reloads in place."

    readonly property string confPath:
        (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/swaync/config.json"

    property var conf: ({})

    function reread() {
        confFile.reload()
        confFile.waitForJob()
        try { conf = JSON.parse(confFile.text()) }
        catch (e) { conf = {}; say("Couldn't parse " + confPath, true) }
    }

    Component.onCompleted: reread()

    // "key": value on a line of its own. Only top-level keys are set here,
    // and none of them share a name with a nested one.
    function setKey(key, value, message) {
        confFile.reload()
        confFile.waitForJob()
        var text = confFile.text()
        var re = new RegExp('^(\\s*"' + key + '"\\s*:\\s*)("[^"]*"|-?[0-9.]+|true|false)', "m")
        var json = JSON.stringify(value)
        var next
        if (re.test(text)) {
            next = text.replace(re, (m, head) => head + json)
        } else {
            // not set yet: add it after the opening brace
            next = text.replace(/^\{\s*\n/, m => m + '  "' + key + '": ' + json + ",\n")
        }
        try { JSON.parse(next) } catch (e) { say("Not written, the edit would break config.json", true); return }
        writeProc.message = message
        writeProc.command = ["sh", "-c", 'printf %s "$2" > "$1" && swaync-client -R -sw >/dev/null', "sh", confPath, next]
        writeProc.running = true
    }

    FileView {
        id: confFile
        path: page.confPath
        blockLoading: true
        printErrors: false
    }

    Process {
        id: writeProc
        property string message: ""
        onExited: code => {
            page.say(code === 0 ? message : "Couldn't write config.json", code !== 0)
            page.reread()
        }
    }

    component Seconds: SettingsField {
        id: sec
        property string key: ""
        property int fallback: 0

        FlyoutStepper {
            anchors.right: parent.right
            width: 170
            readonly property int current: page.conf[sec.key] !== undefined ? Number(page.conf[sec.key]) : sec.fallback
            value: current
            minimum: 0
            maximum: 60
            valueWidth: 64
            displayValue: current === 0 ? "never" : current + " s"
            onStepped: delta => page.setKey(sec.key, Math.max(0, Math.min(60, current + delta)),
                sec.label + ": " + (current + delta === 0 ? "never" : (current + delta) + " s"))
        }
    }

    FlyoutHeading { text: "NOW" }

    FlyoutAction {
        icon: Notifications.dnd ? "󰂛" : "󰂚"
        label: "Do Not Disturb"
        status: !Notifications.available ? "swaync isn't running"
            : Notifications.dnd ? "Popups are held; they still land in the panel" : "Popups show as they arrive"
        checked: Notifications.dnd
        enabled: Notifications.available
        onActivated: Notifications.toggleDnd()
    }

    FlyoutAction {
        icon: "󰎟"
        label: "Clear all"
        status: Notifications.count === 0 ? "Nothing waiting" : Notifications.count + " waiting"
        checkable: false
        enabled: Notifications.available && Notifications.count > 0
        onActivated: Quickshell.execDetached(["swaync-client", "-C", "-sw"])
    }

    FlyoutAction {
        icon: "󰍜"
        label: "Open the panel"
        checkable: false
        enabled: Notifications.available
        onActivated: Notifications.togglePanel()
    }

    Item { width: 1; height: 6 }
    FlyoutHeading { text: "POPUPS" }

    SettingsField {
        label: "Position"
        hint: "where popups and the panel appear"

        Row {
            anchors.right: parent.right
            spacing: 10

            Row {
                spacing: 4
                Repeater {
                    model: ["top", "bottom"]
                    FlyoutChip {
                        required property var modelData
                        text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        selected: page.conf.positionY === modelData
                        onClicked: if (!selected) page.setKey("positionY", modelData, "Popups: " + modelData)
                    }
                }
            }
            Row {
                spacing: 4
                Repeater {
                    model: ["left", "center", "right"]
                    FlyoutChip {
                        required property var modelData
                        text: modelData.charAt(0).toUpperCase() + modelData.slice(1)
                        selected: page.conf.positionX === modelData
                        onClicked: if (!selected) page.setKey("positionX", modelData, "Popups: " + modelData)
                    }
                }
            }
        }
    }

    Seconds {
        key: "timeout"
        label: "Normal"
        hint: "how long a popup stays"
        fallback: 10
    }
    Seconds {
        key: "timeout-low"
        label: "Low priority"
        fallback: 5
    }
    Seconds {
        key: "timeout-critical"
        label: "Critical"
        hint: "never means it stays until dismissed"
        fallback: 0
    }
}
