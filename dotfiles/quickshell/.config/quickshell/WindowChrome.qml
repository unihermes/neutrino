// Neutrino - Quickshell
// ~/.config/quickshell/WindowChrome.qml
//
// Chrome for the standalone windows (System, Keybinds, Settings): the panel
// ground, a title row that drags the window, a close button, and Escape to
// close. Declared first in the window so the content draws over it.
//
// Content can't anchor to `header` (it isn't a sibling), so it positions
// itself at `contentY` instead.

import QtQuick

Item {
    id: root

    // the FloatingWindow this dresses; needs close()
    required property var window
    property string heading: ""
    readonly property int contentY: header.y + header.height + 6
    // takes Escape; focus it after anything else in the window had focus
    readonly property alias keySink: keySink

    anchors.fill: parent

    PanelFrame { anchors.fill: parent }

    // Escape anywhere in the window. A text field with focus takes Escape
    // itself (to clear, or to close an editor), so this only fires when
    // nothing more local wanted it.
    Item {
        id: keySink
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.window.close()
    }

    Item {
        id: header
        x: 16
        y: 12
        width: parent.width - 32
        height: 24

        // drag the window by its title row
        MouseArea {
            anchors.fill: parent
            onPressed: root.window.startSystemMove()
        }

        FlyoutHeading {
            anchors.left: parent.left
            anchors.right: closeBtn.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: root.heading
        }

        Rectangle {
            id: closeBtn
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 20
            height: 20
            radius: Theme.radiusInner
            color: closeMouse.containsMouse ? Theme.overlay : "transparent"

            Text {
                anchors.centerIn: parent
                text: "󰅖"
                color: closeMouse.containsMouse ? Theme.bright : Theme.subtext
                font.family: Theme.fontIcon
                font.pixelSize: Theme.fontIconSize
            }

            MouseArea {
                id: closeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.window.close()
            }
        }
    }
}
