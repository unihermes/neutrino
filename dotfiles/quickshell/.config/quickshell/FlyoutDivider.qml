// Neutrino - Quickshell
// ~/.config/quickshell/FlyoutDivider.qml
//
// A plain rule between groups of rows, for menus that split into sections
// without wanting a label on each one. FlyoutHeading is the labelled
// version of the same idea.
//
// The negative margins match FlyoutRow's: rows bleed 4px past the content
// column on both sides so their hover highlight reaches the panel's inner
// padding, and a divider that stopped short of that would look inset.

import QtQuick

Item {
    id: root

    width: parent ? parent.width : 0
    implicitHeight: 9

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: -4
        anchors.rightMargin: -4
        anchors.verticalCenter: parent.verticalCenter
        height: 1
        color: Theme.border
    }
}
