// Neutrino - Quickshell
// ~/.config/quickshell/FlyoutRow.qml
//
// One line in a flyout: a label, an optional right-aligned value, and a
// click. Rows that are pure readout (battery health, time remaining) set
// `enabled: false` -- that drops the hover highlight and the pointer
// cursor so they don't advertise a click that does nothing.

import QtQuick

Item {
    id: root

    property string label: ""
    property string trailing: ""
    // marks the current/active entry (connected network, paired device)
    property bool highlighted: false
    property bool enabled: true
    // the trailing text is the row's current setting (Top, Grayscale), not
    // a chevron or tick, so it reads like a stepper's value
    property bool trailingIsValue: false

    signal activated()

    width: parent ? parent.width : 0
    implicitHeight: Theme.fs(24)

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -4
        anchors.rightMargin: -4
        radius: Theme.radiusInner
        color: (root.enabled && mouse.containsMouse) ? Theme.overlay : "transparent"
    }

    // left edge tick on the active entry, instead of a fill: a filled row
    // would read as "hovered" next to the hover highlight
    Rectangle {
        anchors.left: parent.left
        anchors.leftMargin: -4
        anchors.verticalCenter: parent.verticalCenter
        width: 2
        height: parent.height - 6
        radius: 1
        color: Theme.bright
        visible: root.highlighted
    }

    Text {
        id: labelText
        anchors.left: parent.left
        anchors.leftMargin: root.highlighted ? 6 : 0
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: trailingText.left
        anchors.rightMargin: 8
        text: root.label
        elide: Text.ElideRight
        color: {
            if (!root.enabled) return Theme.subtext
            if (root.highlighted || mouse.containsMouse) return Theme.bright
            return Theme.text
        }
        font.family: Theme.fontText
        font.pixelSize: Theme.fontBody
    }

    Text {
        id: trailingText
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: root.trailing
        // On a readout row (battery health, humidity) the trailing text is
        // the information itself, so it reads at text weight. On a clickable
        // row it's decoration -- a chevron, a check -- and stays quiet.
        color: root.trailingIsValue ? Theme.bright
            : root.enabled ? Theme.muted : Theme.text
        // icon glyphs turn up here (the check/ban marks on toggle rows),
        // and this is the one font that has them
        font.family: Theme.fontIcon
        font.pixelSize: Theme.fontBody
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: root.enabled
        enabled: root.enabled
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
    }
}
