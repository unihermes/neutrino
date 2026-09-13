// Neutrino - Quickshell
// ~/.config/quickshell/ModuleFrame.qml
//
// The bar's double-bordered chip: an outer stroke plus a second stroke
// inset inside it, wrapped around whatever you put in it. Children are laid
// out in a centred Row.
//
// This exists so the chrome has one definition. BarModule draws an
// icon/label pair in it, and the open-window icons draw a whole row of
// icons in a single one -- the alternative was a second hand-maintained
// lookalike that would drift the first time the border changed.

import QtQuick

Item {
    id: root

    // lit state: brighter strokes and a filled ground
    property bool active: false
    property int spacing: 5
    // per-chip override, for the ones that look cramped at the shared value
    property int padH: Theme.modulePadH

    // Gauge mode. -1 leaves the chip as a plain icon/label chip; 0..1 turns
    // the right-hand side into a bar that fills with the value, and the
    // content is left-aligned beside it instead of centred.
    property real fillValue: -1
    readonly property bool gauge: fillValue >= 0
    property color fillColor: Theme.muted
    // when > 0 the chip is pinned to this width instead of hugging content
    property int fixedWidth: 0

    default property alias content: contentRow.children

    // Slides to its new slot when Bar Widgets reorders the bar; the bar
    // switches this on once startup layout has settled (shell.qml)
    property bool slideX: false
    Behavior on x {
        enabled: root.slideX
        NumberAnimation { duration: Theme.dur(160); easing.type: Easing.OutCubic }
    }

    implicitWidth: frame.width
    implicitHeight: Theme.barHeight

    Rectangle {
        id: frame
        anchors.verticalCenter: parent.verticalCenter
        width: root.fixedWidth > 0
            ? root.fixedWidth
            : contentRow.implicitWidth + root.padH * 2
        height: Theme.moduleHeight
        radius: Theme.radius
        color: root.active ? Theme.overlay : "transparent"
        border.width: 1
        border.color: root.active ? Theme.subtext : Theme.border

        Behavior on color { ColorAnimation { duration: Theme.dur(110) } }

        // inner stroke, inset -- the second half of the double border
        Rectangle {
            anchors.fill: parent
            anchors.margins: 2
            radius: Theme.radiusInner
            color: "transparent"
            border.width: 1
            border.color: root.active ? Theme.muted : Theme.surface
        }

        // Flush inside the double border: the outer stroke sits at 0..1, the
        // inner one at 2..3, so 3 is the first clear pixel. Matching that
        // exactly is what makes the bar touch the border with no gap.
        readonly property int barInset: 3

        // The bar is the whole interior now, with the icon sitting on top of
        // it rather than beside it.
        Rectangle {
            id: track
            visible: root.gauge
            anchors.fill: parent
            anchors.margins: frame.barInset
            // one less than the inner stroke's radius, being one pixel
            // further in, so the curves stay concentric -- floored because
            // the radius is user-settable down to square
            radius: Math.max(0, Theme.radiusInner - 1)
            color: Theme.base

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                // clamped to its own diameter so a nearly-empty bar is still
                // a rounded stub rather than a sliver with clipped corners
                width: root.fillValue <= 0
                    ? 0
                    : Math.max(radius * 2, parent.width * Math.min(1, root.fillValue))
                radius: parent.radius
                color: root.fillColor

                Behavior on width {
                    NumberAnimation { duration: Theme.dur(120); easing.type: Easing.OutCubic }
                }
                Behavior on color { ColorAnimation { duration: Theme.dur(110) } }
            }
        }

        // Drawn after the track, so the icon reads on top of the fill
        // wherever the fill has reached.
        Row {
            id: contentRow
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: root.gauge ? parent.left : undefined
            anchors.leftMargin: root.gauge ? root.padH : 0
            anchors.horizontalCenter: root.gauge ? undefined : parent.horizontalCenter
            spacing: root.spacing
        }
    }
}
