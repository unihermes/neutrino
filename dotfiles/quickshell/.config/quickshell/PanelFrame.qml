// Neutrino - Quickshell
// ~/.config/quickshell/PanelFrame.qml
//
// The panel ground every flyout and standalone window shares: the #141414
// fill, an outer stroke, and a second stroke inset 3px inside it -- the
// "double border". ModuleFrame is the bar chip's tighter version of the same
// look.

import QtQuick

Rectangle {
    radius: Theme.radius
    color: Theme.panel
    border.width: 1
    border.color: Theme.border

    Rectangle {
        anchors.fill: parent
        anchors.margins: 3
        radius: Math.max(0, Theme.radius - 3)
        color: "transparent"
        border.width: 1
        border.color: Theme.muted
    }
}
