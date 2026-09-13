// Neutrino - Quickshell
// ~/.config/quickshell/FlyoutHeading.qml
//
// Section label for a flyout: small caps, then a rule that runs out to the
// right edge -- the same "label cut into a border" motif the rest of the
// repo uses (see the fastfetch box headers).

import QtQuick

Item {
    id: root

    property string text: ""

    width: parent ? parent.width : 0
    implicitHeight: Theme.fs(16)

    Text {
        id: label
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.text
        color: Theme.bright
        font.family: Theme.fontText
        font.pixelSize: Theme.fontSmall
        font.bold: true
        font.letterSpacing: 1
    }

    Rectangle {
        anchors.left: label.right
        anchors.leftMargin: 8
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Theme.border
    }
}
