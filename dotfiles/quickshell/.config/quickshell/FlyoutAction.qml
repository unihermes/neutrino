// Neutrino - Quickshell
// ~/.config/quickshell/FlyoutAction.qml
//
// One Quick Actions row: an icon, a label, an optional status line under it,
// and -- for toggles -- a switch on the right.
//
// Toggles and momentary buttons share this one component rather than the
// buttons being plain FlyoutRows: FlyoutRow has no icon column, so the
// screenshot and picker rows would sit a glyph-width left of the toggles
// above them and the whole page would read as two lists glued together.
//
// The switch mirrors state, it doesn't own it. `checked` is bound to the
// real thing (iwd's Powered, the adapter, the sink), and a click only emits
// activated() -- so a toggle that fails, or that something else flips,
// shows the truth instead of what was last clicked.

import QtQuick

Item {
    id: root

    property string icon: ""
    property string label: ""
    // second line: SSID, device name, volume. Empty collapses the row to
    // a single line.
    property string status: ""
    // false = momentary button: no switch, the row itself is the action
    property bool checkable: true
    property bool checked: false
    property bool enabled: true
    // a glyph in the switch's place on a non-checkable row, e.g. a lock on
    // a setting that can't be turned off
    property string trailingIcon: ""

    signal activated()

    width: parent ? parent.width : 0
    implicitHeight: Theme.fs(status !== "" ? 36 : 26)

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -4
        anchors.rightMargin: -4
        radius: Theme.radiusInner
        color: (root.enabled && mouse.containsMouse) ? Theme.overlay : "transparent"
    }

    // Fixed-width icon column, so labels line up whatever the glyph's own
    // advance is -- Nerd Font icons vary from 9 to 17px wide.
    Item {
        id: iconCell
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: parent.height

        Text {
            anchors.centerIn: parent
            text: root.icon
            color: !root.enabled ? Theme.muted
                : (root.checkable && !root.checked) ? Theme.subtext
                : Theme.bright
            font.family: Theme.fontIcon
            font.pixelSize: Theme.fontIconSize
        }
    }

    Column {
        anchors.left: iconCell.right
        anchors.leftMargin: 8
        anchors.right: root.checkable ? toggle.left
            : (root.trailingIcon !== "" ? trailing.left : parent.right)
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: root.label
            elide: Text.ElideRight
            color: !root.enabled ? Theme.subtext
                : mouse.containsMouse ? Theme.bright
                : Theme.text
            font.family: Theme.fontText
            font.pixelSize: Theme.fontBody
        }

        Text {
            visible: root.status !== ""
            width: parent.width
            text: root.status
            elide: Text.ElideRight
            color: Theme.subtext
            font.family: Theme.fontText
            font.pixelSize: Theme.fontSmall
        }
    }

    // The switch. Lightness carries on/off, as everywhere else in the shell:
    // a bright track with a dark knob is on, a dark track with a dim knob off.
    Rectangle {
        id: toggle
        visible: root.checkable
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 26
        height: 14
        radius: height / 2
        color: root.checked ? Theme.text : Theme.surface
        border.width: 1
        border.color: root.checked ? Theme.text : Theme.border

        Behavior on color { ColorAnimation { duration: Theme.dur(110) } }

        Rectangle {
            width: 8
            height: 8
            radius: 4
            anchors.verticalCenter: parent.verticalCenter
            x: root.checked ? parent.width - width - 3 : 3
            color: root.checked ? Theme.base : Theme.muted

            Behavior on x { NumberAnimation { duration: Theme.dur(110); easing.type: Easing.OutCubic } }
        }
    }

    Text {
        id: trailing
        visible: !root.checkable && root.trailingIcon !== ""
        anchors.right: parent.right
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        text: root.trailingIcon
        color: Theme.muted
        font.family: Theme.fontIcon
        font.pixelSize: Theme.fontIconSize
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
