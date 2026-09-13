// Neutrino - Quickshell
// ~/.config/quickshell/FlyoutInput.qml
//
// A single-line text field sized like a FlyoutRow, for the one thing in the
// bar that needs typing: a Wi-Fi passphrase.
//
// The panel it sits in must ask for keyboard focus (FlyoutPanel.wantsKeyboard)
// -- a layer-shell surface gets no key events at all otherwise, and the field
// would look focused while silently dropping every keystroke.

import QtQuick

Item {
    id: root

    property string placeholder: ""
    property alias text: field.text
    property bool echoPassword: true

    signal accepted()
    // Arrow keys and Escape, for fields that drive a list below them. Emitted
    // from the field itself because it holds focus -- the list never sees a
    // key event while the cursor is here.
    signal upPressed()
    signal downPressed()
    signal escapePressed()

    width: parent ? parent.width : 0
    implicitHeight: Theme.fs(26)

    function forceFocus() {
        field.forceActiveFocus()
        field.selectAll()
    }

    Rectangle {
        anchors.fill: parent
        anchors.leftMargin: -4
        anchors.rightMargin: -4
        radius: Theme.radiusInner
        color: Theme.surface
        border.width: 1
        border.color: field.activeFocus ? Theme.subtext : Theme.border
    }

    Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        visible: field.text === ""
        text: root.placeholder
        color: Theme.muted
        font.family: Theme.fontText
        font.pixelSize: Theme.fontBody
    }

    TextInput {
        id: field
        anchors.fill: parent
        anchors.leftMargin: 2
        anchors.rightMargin: 2
        verticalAlignment: TextInput.AlignVCenter
        color: Theme.bright
        selectionColor: Theme.muted
        selectedTextColor: Theme.bright
        font.family: Theme.fontText
        font.pixelSize: Theme.fontBody
        echoMode: root.echoPassword ? TextInput.Password : TextInput.Normal
        // the panel is dismissed by click-off or Escape, so Enter is the only
        // key this needs to act on itself
        onAccepted: root.accepted()
        Keys.onUpPressed: root.upPressed()
        Keys.onDownPressed: root.downPressed()
        Keys.onEscapePressed: root.escapePressed()
    }
}
