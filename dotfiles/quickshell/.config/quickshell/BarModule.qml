// Neutrino - Quickshell
// ~/.config/quickshell/BarModule.qml
//
// One clickable module in the bar: an icon, an optional readout next to it
// (volume/brightness percentages, battery level, the clock), and the click
// that opens its flyout. The chip itself is ModuleFrame.
//
// The frame is wrapped in a full-height Item rather than being the root, so
// the click area covers the bar's whole height, not just the chip.

import QtQuick

Item {
    id: root

    property string icon: ""
    property string label: ""
    // highlights the module while its flyout is open
    property bool active: false
    // dims the icon when the thing it represents is off/absent
    property bool dimmed: false
    property bool acceptWheel: false
    property int padH: Theme.modulePadH
    // -1 for a normal chip; 0..1 replaces the readout with a fill bar and
    // the exact number moves into the flyout
    property real fillValue: -1
    property color fillColor: Theme.muted
    property int fixedWidth: 0
    // caps the label and elides it, for text of unbounded length (a track
    // title); 0 lets the label take whatever width it needs
    property int labelMaxWidth: 0
    // overrides the lightness-based colour, for the few modules whose whole
    // point is to be noticed (privacy, failed units)
    property color iconColor: "transparent"

    signal activated()

    // Slides to its new slot when Bar Widgets reorders the bar; the bar
    // switches this on once startup layout has settled (shell.qml)
    property bool slideX: false
    Behavior on x {
        enabled: root.slideX
        NumberAnimation { duration: Theme.dur(160); easing.type: Easing.OutCubic }
    }
    signal middleClicked()
    signal rightClicked()
    signal wheeled(int delta)

    // Gauge icons are always bright: they sit on top of the fill, and the
    // fill sweeps under them, so anything dimmer loses contrast as it passes.
    readonly property color fg: (active || fillValue >= 0)
        ? Theme.bright
        : (dimmed ? Theme.muted : Theme.text)

    implicitWidth: frame.implicitWidth
    implicitHeight: Theme.barHeight

    ModuleFrame {
        id: frame
        anchors.centerIn: parent
        active: root.active
        padH: root.padH
        fillValue: root.fillValue
        fillColor: root.fillColor
        fixedWidth: root.fixedWidth

        Text {
            id: iconText
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            text: root.icon
            color: root.iconColor.a > 0 ? root.iconColor : root.fg
            font.family: Theme.fontIcon
            font.pixelSize: Theme.iconSize
        }

        Text {
            id: labelText
            anchors.verticalCenter: parent.verticalCenter
            // Centring a Text centres its *line box*, which carries the
            // font's full ascent and descent -- so digits, which use neither,
            // sit visibly high. Measured at 1.5-2px here, and it scales with
            // the font size, so it's derived rather than hardcoded: shift
            // down by the gap between the line box's centre and the ink's.
            anchors.verticalCenterOffset: root.inkNudge(labelInk)
            visible: root.label !== ""
            text: root.label
            width: root.labelMaxWidth > 0 ? Math.min(implicitWidth, root.labelMaxWidth) : implicitWidth
            elide: Text.ElideRight
            color: root.fg
            font.family: Theme.fontText
            font.pixelSize: Theme.barLabelSize
        }
    }

    // A fixed reference string, not the live text: per-glyph ink varies, and
    // following the label would make it bob every time the number changed.
    TextMetrics {
        id: labelInk
        font: labelText.font
        text: "0"
    }

    function inkNudge(m) {
        var line = (m.boundingRect.top + m.boundingRect.bottom) / 2
        var ink  = (m.tightBoundingRect.top + m.tightBoundingRect.bottom) / 2
        return line - ink
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton) root.middleClicked()
            else if (mouse.button === Qt.RightButton) root.rightClicked()
            else root.activated()
        }
        onWheel: wheel => {
            if (root.acceptWheel) root.wheeled(wheel.angleDelta.y > 0 ? 1 : -1)
        }
    }
}
