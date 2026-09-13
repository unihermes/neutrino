// Neutrino - Quickshell
// ~/.config/quickshell/FailedUnits.qml
//
// systemd units in the failed state, system and user, for a bar module that
// only appears when there are any. It exists because a failed unit is
// otherwise invisible: on 2026-09-12 the polkit agent sat failed for over an
// hour after a compositor crash, and nothing on screen said so.
//
// Polled every 30s. systemctl answers in milliseconds, and failures are
// rare enough that half a minute's delay in noticing one doesn't matter.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // [{ name, user }]
    property var units: []
    readonly property int count: units.length

    function refresh() { if (!probe.running) probe.running = true }

    // status and recent log in a terminal, held open until a key is pressed
    function showLog(u) {
        var scope = u.user ? "--user " : ""
        Quickshell.execDetached(["alacritty", "--class", "neutrino-unit-log", "-e", "sh", "-c",
            "systemctl " + scope + "status --no-pager " + u.name + "; echo; "
            + "journalctl " + scope + "-u " + u.name + " -n 40 --no-pager; echo; "
            + "read -rsn1 -p 'press any key to close'"])
    }

    // System units go through polkit, so these prompt for a password there.
    function restart(u) { act(u, "restart") }
    function clear(u)   { act(u, "reset-failed") }

    function act(u, verb) {
        var cmd = ["systemctl"]
        if (u.user) cmd.push("--user")
        cmd.push(verb, u.name)
        actProc.command = cmd
        actProc.running = true
    }

    Process {
        id: actProc
        command: ["true"]
        onExited: root.refresh()
    }

    Process {
        id: probe
        command: ["sh", "-c",
            "systemctl --failed --plain --no-legend 2>/dev/null | awk '{print \"system \" $1}'; "
            + "systemctl --user --failed --plain --no-legend 2>/dev/null | awk '{print \"user \" $1}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = []
                var lines = text.trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var f = lines[i].trim().split(" ")
                    if (f.length === 2 && f[1] !== "") out.push({ name: f[1], user: f[0] === "user" })
                }
                root.units = out
            }
        }
    }

    Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }
}
