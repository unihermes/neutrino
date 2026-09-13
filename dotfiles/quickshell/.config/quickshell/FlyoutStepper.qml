// Neutrino - Quickshell
// ~/.config/quickshell/FlyoutStepper.qml
//
// An integer setting in a flyout: a label, a minus, the value, a plus.
//
// A stepper rather than Slider.qml, which the volume and brightness panels
// use. Those are 0-100 and approximate -- you drag until it looks right.
// These are small exact integers where the whole range is a dozen steps and
// every one is visible, so a 200px track would make single-pixel changes a
// game of aim. The row still shows the range so the ends aren't a surprise.

import QtQuick

Item {
    id: root

    property string label: ""
    property int value: 0
    property int minimum: 0
    property int maximum: 100
    property string suffix: ""
    // shown in place of value + suffix, for a stepper whose integer is a
    // count of steps (0.1s of sensitivity) rather than the setting itself
    property string displayValue: ""
    // left offset for the label, to line up under an icon column (a
    // FlyoutAction's labels start 28px in)
    property int labelInset: 0
    // the value cell is fixed-width so the buttons don't shuffle; widen it
    // for values with more digits than the appearance metrics have
    property int valueWidth: 34
    readonly property int scaledValueWidth: Theme.fs(valueWidth)

    signal stepped(int delta)

    width: parent ? parent.width : 0
    implicitHeight: Theme.fs(24)

    Text {
        anchors.left: parent.left
        anchors.leftMargin: root.labelInset
        anchors.verticalCenter: parent.verticalCenter
        text: root.label
        color: Theme.text
        font.family: Theme.fontText
        font.pixelSize: Theme.fontBody
    }

    Row {
        id: controls
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        component Button: Rectangle {
            id: btn
            property string glyph: ""
            // at an end of the range the button is inert rather than hidden,
            // so the row doesn't reflow every time you reach a limit
            property bool live: true
            signal pressed()

            width: Theme.fs(18)
            height: Theme.fs(18)
            radius: Math.max(0, Theme.radiusInner - 1)
            color: (btn.live && ma.containsMouse) ? Theme.overlay : "transparent"
            border.width: 1
            border.color: btn.live ? Theme.border : Theme.surface

            Text {
                anchors.centerIn: parent
                text: btn.glyph
                color: btn.live ? (ma.containsMouse ? Theme.bright : Theme.text) : Theme.surface
                font.family: Theme.fontText
                font.pixelSize: Theme.fontBody
            }

            MouseArea {
                id: ma
                anchors.fill: parent
                hoverEnabled: btn.live
                enabled: btn.live
                cursorShape: Qt.PointingHandCursor
                onClicked: btn.pressed()
            }
        }

        Button {
            glyph: "−"
            live: root.value > root.minimum
            onPressed: root.stepped(-1)
        }

        // Fixed width, wide enough for the longest value the range can
        // produce: letting it hug the text would shuffle both buttons
        // sideways every time the number gained or lost a digit.
        Item {
            width: root.scaledValueWidth
            height: Theme.fs(18)

            Text {
                anchors.centerIn: parent
                text: root.displayValue !== "" ? root.displayValue : root.value + root.suffix
                color: Theme.bright
                font.family: Theme.fontText
                font.pixelSize: Theme.fontBody
            }
        }

        Button {
            glyph: "+"
            live: root.value < root.maximum
            onPressed: root.stepped(1)
        }
    }
}
