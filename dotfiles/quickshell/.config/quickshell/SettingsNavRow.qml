// Neutrino - Quickshell
// ~/.config/quickshell/SettingsNavRow.qml
//
// One entry in the Settings window's sidebar: an icon column, a label, and
// the left-edge tick FlyoutRow uses for the current entry -- a fill would
// read as hover next to the hover highlight.

import QtQuick

Item {
    id: root

    property string icon: ""
    property string label: ""
    property bool selected: false
    // a trailing arrow for entries that open somewhere else (Appearance)
    property bool external: false

    signal clicked()

    width: parent ? parent.width : 0
    implicitHeight: Theme.fs(28)

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusInner
        color: root.selected ? Theme.surface
            : mouse.containsMouse ? Theme.overlay : "transparent"
    }

    Rectangle {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: parent.height - 8
        radius: 1
        color: Theme.bright
        visible: root.selected
    }

    Item {
        id: iconCell
        x: 8
        width: 20
        height: parent.height

        Text {
            anchors.centerIn: parent
            text: root.icon
            color: root.selected || mouse.containsMouse ? Theme.bright : Theme.subtext
            font.family: Theme.fontIcon
            font.pixelSize: Theme.fontIconSize
        }
    }

    Text {
        anchors.left: iconCell.right
        anchors.leftMargin: 8
        anchors.right: arrow.left
        anchors.rightMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        elide: Text.ElideRight
        color: root.selected || mouse.containsMouse ? Theme.bright : Theme.text
        font.family: Theme.fontText
        font.pixelSize: Theme.fontBody
    }

    Text {
        id: arrow
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.external ? "󰁔" : ""
        color: Theme.muted
        font.family: Theme.fontIcon
        font.pixelSize: Theme.fontSmall
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
