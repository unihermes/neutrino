// Neutrino - Quickshell
// ~/.config/quickshell/PpdProfile.qml
//
// power-profiles-daemon's active profile, for the battery flyout and the
// Settings window's Power page.
//
// Over PPD's DBus interface via busctl. Deliberately not powerprofilesctl:
// that is a python script that imports gi.repository, so it needs
// python-gobject pulled in just to read one string, and it is not a
// dependency of the daemon. busctl ships with systemd. PPD is
// DBus-activatable, so the first read starts it even if the unit was never
// enabled.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // "power-saver" | "balanced" | "performance"; "" means PPD is not
    // answering, which the UI says out loud rather than showing dead buttons
    property string profile: ""
    readonly property bool busy: setProc.running

    // a set() has settled; error is busctl's first line of complaint
    signal setFinished(bool ok, string error)

    readonly property var busPath: ["org.freedesktop.UPower.PowerProfiles",
        "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles"]

    function refresh() { readProc.running = true }

    function set(name) {
        // optimistic, so the tick moves the instant it is clicked; the
        // re-read on exit settles it if PPD refuses or degrades it
        profile = name
        setProc.command = ["busctl", "set-property"].concat(busPath, ["ActiveProfile", "s", name])
        setProc.running = true
    }

    Process {
        id: readProc
        running: true
        // prints: s "balanced"
        command: ["sh", "-c", 'busctl get-property "$@" ActiveProfile 2>/dev/null | cut -d\'"\' -f2', "sh"].concat(root.busPath)
        stdout: StdioCollector {
            onStreamFinished: root.profile = text.trim()
        }
    }

    Process {
        id: setProc
        stderr: StdioCollector { id: setErr }
        onExited: code => {
            root.setFinished(code === 0, setErr.text.trim().split("\n")[0])
            root.refresh()
        }
    }
}
