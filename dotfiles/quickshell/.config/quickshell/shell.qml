// Neutrino - Quickshell entry point
// ~/.config/quickshell/shell.qml
//
// Deliberately minimal: a top bar with a clock, enough to prove Quickshell
// launches and draws under Hyprland on VMware. Build outward from here.

import Quickshell
import QtQuick

ShellRoot {
    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData

            anchors {
                top: true
                left: true
                right: true
            }
            implicitHeight: 32
            color: "#11111b"

            Text {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                color: "#cdd6f4"
                font.family: "Ubuntu Nerd Font"
                font.pixelSize: 13
                text: "Neutrino"
            }

            Text {
                id: clock
                anchors.centerIn: parent
                color: "#cdd6f4"
                font.family: "UbuntuMono Nerd Font"
                font.pixelSize: 13
                text: Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm")
            }

            Timer {
                interval: 1000
                running: true
                repeat: true
                onTriggered: clock.text =
                    Qt.formatDateTime(new Date(), "ddd d MMM  HH:mm")
            }
        }
    }
}
