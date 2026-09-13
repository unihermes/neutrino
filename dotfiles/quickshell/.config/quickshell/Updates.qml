// Neutrino - Quickshell
// ~/.config/quickshell/Updates.qml
//
// Pending package updates, repo and AUR, for a bar module that only appears
// when there are some.
//
// checkupdates (pacman-contrib) rather than `pacman -Qu`: it syncs a
// throwaway copy of the database in /tmp, so it sees what's new without
// root and without touching the real sync db -- a `pacman -Sy` here would
// set up a partial upgrade. `yay -Qua` asks the AUR's RPC for the rest.
//
// First check two minutes after login, when the network has had time to
// come up, then hourly.

pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // [{ name, from, to, aur }]
    property var packages: []
    readonly property int count: packages.length
    readonly property int aurCount: packages.filter(p => p.aur).length
    property bool available: false      // checkupdates is installed
    property bool checking: false
    property var lastChecked: null

    function refresh() {
        if (!available || checkProc.running) return
        checking = true
        checkProc.running = true
    }

    // yay does repo and AUR in one pass, unattended after the one sudo
    // password prompt:
    //   --sudoloop       keeps sudo's timestamp fresh, so a long AUR build
    //                    doesn't ask again when pacman installs at the end
    //   --noconfirm      takes pacman's default at every [Y/n]
    //   --answer* None   skips yay's clean-build / diff / PKGBUILD-edit menus
    //   --removemake     drops build-only deps without asking
    // On success the terminal closes itself with a notification; on failure
    // it stays open so the error can be read. Either way the list is
    // re-checked once it closes.
    function update() {
        if (updateProc.running) return
        updateProc.running = true
    }

    // Re-checked until found, for the same reason as the visualizer's cava
    // check: pacman-contrib tends to be installed with the bar already up.
    Process {
        id: availProbe
        running: true
        command: ["sh", "-c", "command -v checkupdates"]
        onExited: code => root.available = (code === 0)
    }

    Timer {
        interval: 10000
        repeat: true
        running: !root.available
        onTriggered: availProbe.running = true
    }

    Process {
        id: checkProc
        command: ["sh", "-c",
            "checkupdates 2>/dev/null | sed 's/^/repo /'; "
            + "command -v yay >/dev/null && yay -Qua 2>/dev/null | sed 's/^/aur /'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = []
                var lines = text.trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    // "repo name 1.0-1 -> 1.1-1"
                    var f = lines[i].trim().split(/\s+/)
                    if (f.length >= 5 && f[3] === "->")
                        out.push({ name: f[1], from: f[2], to: f[4], aur: f[0] === "aur" })
                }
                out.sort((a, b) => a.name.localeCompare(b.name))
                root.packages = out
                root.lastChecked = new Date()
            }
        }
        onExited: root.checking = false
    }

    Process {
        id: updateProc
        command: ["alacritty", "--class", "neutrino-update", "-e", "sh", "-c",
            "yay -Syu --sudoloop --noconfirm --answerclean None --answerdiff None "
            + "--answeredit None --removemake; "
            + "if [ $? -eq 0 ]; then notify-send -a Updates 'System updated' 'All packages are up to date'; "
            + "else echo; echo 'Update failed -- see above.'; read -rsn1 -p 'press any key to close'; fi"]
        onExited: root.refresh()
    }

    Timer {
        id: firstCheck
        interval: 120000
        running: root.available
        onTriggered: root.refresh()
    }

    Timer {
        interval: 3600000
        repeat: true
        running: root.available
        onTriggered: root.refresh()
    }
}
