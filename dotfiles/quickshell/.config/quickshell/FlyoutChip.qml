// Neutrino - Quickshell
// ~/.config/quickshell/FlyoutChip.qml
//
// A small bordered button for inline actions inside a flyout row -- the
// Log / Restart / Clear on a failed unit, the media transport controls --
// where a full-width FlyoutRow per action would bury the list under them.

import QtQuick

Item {
    id: root

    property string text: ""
    // icon glyphs render bigger than letters at the same size
    property bool glyph: false
    property bool enabled: true
    // lit, for the current choice in a pair (°F / °C)
    property bool selected: false

    signal clicked()

    implicitWidth: label.implicitWidth + (glyph ? 14 : 12)
    implicitHeight: Theme.fs(20)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusInner
        color: root.selected ? Theme.overlay
            : (root.enabled && mouse.containsMouse) ? Theme.surface : "transparent"
        border.width: 1
        border.color: root.selected ? Theme.muted
            : (root.enabled && mouse.containsMouse) ? Theme.muted : Theme.border
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.text
        color: !root.enabled ? Theme.muted
            : (root.selected || mouse.containsMouse) ? Theme.bright : Theme.text
        font.family: root.glyph ? Theme.fontIcon : Theme.fontText
        font.pixelSize: root.glyph ? Theme.fontIconSize : Theme.fontBody
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.enabled
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
