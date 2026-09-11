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
import QtQuick

ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: bar
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 30
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
                        required property int index
                        readonly property bool active:
                            Hyprland.focusedWorkspace
                                ? Hyprland.focusedWorkspace.id === index + 1
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
                            text: parent.index + 1
                            color: parent.active ? "#0b0b0b" : bar.cMuted
                            font.family: "UbuntuMono Nerd Font"
                            font.pixelSize: 10
                            font.bold: parent.active
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Hyprland.dispatch("workspace " + (parent.index + 1))
                        }
                    }
                }
            }

            // --- centre: clock ----------------------------------------
            Text {
                id: clock
                anchors.centerIn: parent
                color: bar.cBright
                font.family: "UbuntuMono Nerd Font"
                font.pixelSize: 13
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
                    font.family: "UbuntuMono Nerd Font"
                    font.pixelSize: 12
                }

                Text {
                    visible: bar.battery !== ""
                    // charging is shown by weight, not by a colour, since the
                    // whole palette is grayscale
                    text: "bat " + bar.battery + "%"
                    color: parseInt(bar.battery) <= 15 ? bar.cBright : bar.cSubtext
                    font.family: "UbuntuMono Nerd Font"
                    font.pixelSize: 12
                    font.bold: bar.batteryState === "Charging"
                }

                Text {
                    text: Qt.formatDateTime(new Date(), "ddd d MMM")
                    color: bar.cText
                    font.family: "UbuntuMono Nerd Font"
                    font.pixelSize: 12
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
    }
}
