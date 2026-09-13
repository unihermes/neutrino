// Neutrino - Quickshell
// ~/.config/quickshell/Notifications.qml
//
// swaync's state, for the bar's notification module: unread count and Do Not
// Disturb. swaync stays the notification daemon -- this only watches it.
//
// `swaync-client -swb` is a subscription, not a poll: it prints one line of
// JSON immediately and another on every change, in Waybar's format, where
// "alt" carries the state ("notification", "none", "dnd-notification",
// "dnd-none", "inhibited-..."). If swaync restarts the subscription ends,
// so it's re-attached after a short pause.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property int count: 0
    property bool dnd: false
    // false until swaync has answered at least once
    property bool available: false

    function togglePanel() { Quickshell.execDetached(["swaync-client", "-t", "-sw"]) }
    function toggleDnd()   { Quickshell.execDetached(["swaync-client", "-d", "-sw"]) }

    Process {
        id: sub
        running: true
        command: ["swaync-client", "-swb"]
        stdout: SplitParser {
            onRead: line => {
                try {
                    var j = JSON.parse(line)
                    root.count = parseInt(j.text) || 0
                    root.dnd = String(j.alt).startsWith("dnd")
                    root.available = true
                } catch (e) {}
            }
        }
        onExited: {
            root.available = false
            reattach.restart()
        }
    }

    Timer {
        id: reattach
        interval: 3000
        onTriggered: sub.running = true
    }
}
