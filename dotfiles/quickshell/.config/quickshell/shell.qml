// Neutrino - Quickshell
// ~/.config/quickshell/shell.qml
//
// A basic status bar: workspace pills on the left, clock in the middle,
// volume / battery / date on the right. Same grayscale ramp as the rest of
// the repo -- nothing here is coloured, only lighter or darker.
//
// Quickshell's QML API moves quickly. If the bar does not appear, run
// `quickshell` from a terminal inside the session: QML errors go to stderr
// with a file and line number, and they are usually a renamed import.

import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Widgets
import QtQuick

ShellRoot {
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

            // shared between the bar (which owns the toggle button) and the
            // menu (a separate layer-shell surface, so it can float over
            // everything without the bar reserving space for it)
            property bool powerMenuOpen: false

        PanelWindow {
            id: bar
            screen: screenScope.modelData

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 34
            color: "#121212"

            // ramp
            readonly property color cBorder:  "#303030"
            readonly property color cMuted:   "#4d4d4d"
            readonly property color cSubtext: "#7a7a7a"
            readonly property color cText:    "#c2c2c2"
            readonly property color cBright:  "#ebebeb"

            property string battery: ""
            property string batteryState: ""
            property string volume: ""

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
                        if (!cls) continue
                        var entry = DesktopEntries.heuristicLookup(cls)
                        var path = entry ? Quickshell.iconPath(entry.icon, true) : ""
                        if (path) icons.push({ source: path, address: tls[j].address })
                    }
                    break
                }
                return icons
            }

            // hairline under the bar, so it reads as a surface rather than a
            // strip of background
            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: bar.cBorder
            }

            // --- left: workspaces -------------------------------------
            Row {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 4

                Repeater {
                    model: 5

                    Rectangle {
                        id: pill
                        required property int index
                        readonly property int wsId: index + 1
                        readonly property bool active:
                            Hyprland.focusedWorkspace
                                ? Hyprland.focusedWorkspace.id === wsId
                                : false

                        width: active ? 22 : 16
                        height: 16
                        radius: 4
                        color: active ? bar.cText : "#1d1d1d"
                        border.width: 1
                        border.color: active ? bar.cText : bar.cBorder

                        Behavior on width {
                            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
                        }
                        Behavior on color {
                            ColorAnimation { duration: 130 }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: pill.wsId
                            color: pill.active ? "#0b0b0b" : bar.cMuted
                            font.family: "ProggyVector"
                            font.pointSize: 11
                            font.bold: pill.active
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Hyprland.dispatch("hl.dsp.focus({workspace=" + pill.wsId + "})")
                        }
                    }
                }

                // icons for whatever is open on the focused workspace, right
                // after the pills
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4

                    Repeater {
                        model: bar.focusedWorkspaceIcons()

                        IconImage {
                            required property var modelData
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

            // --- centre: clock ----------------------------------------
            Text {
                id: clock
                anchors.centerIn: parent
                color: bar.cBright
                font.family: "ProggyVector"
                font.pointSize: 12
                text: Qt.formatDateTime(new Date(), "HH:mm")
            }

            // --- right: volume, battery, date -------------------------
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 14

                Text {
                    visible: bar.volume !== ""
                    text: "vol " + bar.volume
                    color: bar.cSubtext
                    font.family: "ProggyVector"
                    font.pointSize: 12
                }

                Text {
                    visible: bar.battery !== ""
                    // charging is shown by weight, not by a colour, since the
                    // whole palette is grayscale
                    text: "bat " + bar.battery + "%"
                    color: parseInt(bar.battery) <= 15 ? bar.cBright : bar.cSubtext
                    font.family: "ProggyVector"
                    font.pointSize: 12
                    font.bold: bar.batteryState === "Charging"
                }

                Text {
                    text: Qt.formatDateTime(new Date(), "ddd d MMM")
                    color: bar.cText
                    font.family: "ProggyVector"
                    font.pointSize: 12
                }

                Text {
                    text: "⏻"
                    color: screenScope.powerMenuOpen ? bar.cBright : bar.cSubtext
                    font.family: "ProggyVector"
                    font.pointSize: 12

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -4
                        cursorShape: Qt.PointingHandCursor
                        onClicked: screenScope.powerMenuOpen = !screenScope.powerMenuOpen
                    }
                }
            }

            // --- data -------------------------------------------------
            // BAT* rather than BAT0: laptops disagree about the number, and a
            // desktop simply matches nothing and leaves the field hidden.
            Process {
                id: batCapacity
                command: ["sh", "-c", "cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: bar.battery = text.trim()
                }
            }

            Process {
                id: batStatus
                command: ["sh", "-c", "cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: bar.batteryState = text.trim()
                }
            }

            Process {
                id: volProc
                command: ["sh", "-c", "wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{printf \"%d\", $2*100}'"]
                running: true
                stdout: StdioCollector {
                    onStreamFinished: bar.volume = text.trim()
                }
            }

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: {
                    clock.text = Qt.formatDateTime(new Date(), "HH:mm")
                    volProc.running = true
                }
            }

            Timer {
                interval: 30000
                running: true
                repeat: true
                onTriggered: {
                    batCapacity.running = true
                    batStatus.running = true
                }
            }
        }

        // --- power menu -----------------------------------------------
        // Its own layer-shell surface rather than something drawn inside
        // the bar: a panel clips to its own surface, so a dropdown drawn
        // in the bar would be cut off at the bar's bottom edge.
        PanelWindow {
            id: powerMenu
            screen: screenScope.modelData
            visible: screenScope.powerMenuOpen

            anchors {
                top: true
                right: true
            }
            margins.right: 8
            implicitWidth: 130
            implicitHeight: menuColumn.implicitHeight + 8
            color: "#161616"
            // never reserve screen space -- it floats over the windows
            // underneath instead of shoving them aside while it is open
            exclusiveZone: 0

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.width: 1
                border.color: bar.cBorder
                radius: 4
            }

            Column {
                id: menuColumn
                anchors.centerIn: parent
                width: parent.width

                Repeater {
                    model: [
                        { label: "Lock",      action: "lock" },
                        { label: "Sleep",     action: "sleep" },
                        { label: "Log Out",   action: "logout" },
                        { label: "Reboot",    action: "reboot" },
                        { label: "Shut Down", action: "poweroff" },
                    ]

                    Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 28
                        color: itemMouse.containsMouse ? "#242424" : "transparent"

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.left: parent.left
                            anchors.leftMargin: 12
                            text: parent.modelData.label
                            color: itemMouse.containsMouse ? bar.cBright : bar.cText
                            font.family: "ProggyVector"
                            font.pointSize: 11
                        }

                        MouseArea {
                            id: itemMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                screenScope.powerMenuOpen = false
                                var action = parent.modelData.action
                                if (action === "lock") {
                                    Quickshell.execDetached(["hyprlock"])
                                } else if (action === "sleep") {
                                    Quickshell.execDetached(["systemctl", "suspend"])
                                } else if (action === "logout") {
                                    Hyprland.dispatch("hl.dsp.exit()")
                                } else if (action === "reboot") {
                                    Quickshell.execDetached(["systemctl", "reboot"])
                                } else if (action === "poweroff") {
                                    Quickshell.execDetached(["systemctl", "poweroff"])
                                }
                            }
                        }
                    }
                }
            }
        }

        }
    }
}
