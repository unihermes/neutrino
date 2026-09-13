// Neutrino - Quickshell
// ~/.config/quickshell/Slider.qml
//
// Hand-rolled rather than QtQuick.Controls' Slider: Controls pulls in a
// style plugin and its own theming, which would fight the grayscale ramp
// for the sake of one widget. This is a track, a fill, and a drag.

import QtQuick

Item {
    id: root

    property real value: 0          // 0..100

    // Fired continuously while dragging, so the backend follows the
    // handle instead of only catching up on release.
    signal moved(real value)

    implicitHeight: 16

    function valueAt(px) {
        return Math.round(Math.max(0, Math.min(1, px / width)) * 100)
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 10
        radius: 5
        color: Theme.surface
        border.width: 1
        border.color: Theme.muted

        Rectangle {
            x: 1
            y: 1
            height: parent.height - 2
            width: Math.max(0, Math.min(1, root.value / 100)) * (parent.width - 2)
            radius: 4
            color: Theme.text
        }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onPressed: mouse => root.moved(root.valueAt(mouse.x))
        onPositionChanged: mouse => {
            if (pressed) root.moved(root.valueAt(mouse.x))
        }
    }
}
