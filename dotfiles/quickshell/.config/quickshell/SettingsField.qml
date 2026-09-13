// Neutrino - Quickshell
// ~/.config/quickshell/SettingsField.qml
//
// One setting on a Settings page: a label with an optional hint under it on
// the left, and whatever controls it on the right (chips, a stepper's
// buttons, a slider, a field). Rows grow to fit a hint or a wrapping Flow of
// chips rather than clipping them.

import QtQuick

Item {
    id: root

    property string label: ""
    property string hint: ""
    // width of the label column; controls get the rest
    property int labelWidth: 240

    default property alias control: slot.data

    width: parent ? parent.width : 0
    implicitHeight: Math.max(Theme.fs(28), labels.implicitHeight + 6, slot.childrenRect.height + 6)

    Column {
        id: labels
        width: root.labelWidth - 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
            width: parent.width
            text: root.label
            elide: Text.ElideRight
            color: Theme.text
            font.family: Theme.fontText
            font.pixelSize: Theme.fontBody
        }

        Text {
            width: parent.width
            visible: root.hint !== ""
            text: root.hint
            wrapMode: Text.WordWrap
            color: Theme.subtext
            font.family: Theme.fontText
            font.pixelSize: Theme.fontSmall
        }
    }

    // controls are right-aligned by their own anchors inside this slot
    Item {
        id: slot
        anchors.left: parent.left
        anchors.leftMargin: root.labelWidth
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        height: childrenRect.height
    }
}
