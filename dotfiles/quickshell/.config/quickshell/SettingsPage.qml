// Neutrino - Quickshell
// ~/.config/quickshell/SettingsPage.qml
//
// The frame every Settings page shares: a heading, one line saying what the
// page changes and where it lands, a status line, and a scrolling column for
// the page's own rows.
//
// Pages are created by the window's Loader when shown and destroyed when
// left, so a page reads its backing store fresh in Component.onCompleted and
// never has to reconcile with state from an earlier visit.

import QtQuick

Item {
    id: root

    property string title: ""
    property string description: ""
    // the page's last result: "Saved", a Hyprland complaint, a missing tool
    property string notice: ""
    property bool noticeIsError: false
    // off for a page that manages its own scrolling (Keybinds)
    property bool scrolls: true

    default property alias content: col.data
    // height available to content below the header, for non-scrolling pages
    readonly property real bodyHeight: height - header.height - 10

    function say(msg, isError) {
        notice = msg
        noticeIsError = !!isError
    }

    Column {
        id: header
        width: parent.width
        spacing: 4

        FlyoutHeading { text: root.title.toUpperCase() }

        Text {
            width: parent.width
            visible: text !== ""
            text: root.description
            wrapMode: Text.WordWrap
            color: Theme.subtext
            font.family: Theme.fontText
            font.pixelSize: Theme.fontSmall
        }

        Text {
            width: parent.width
            height: Theme.fs(16)
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            text: root.notice
            color: root.noticeIsError ? Theme.alert : Theme.text
            font.family: Theme.fontText
            font.pixelSize: Theme.fontSmall
        }
    }

    Item {
        anchors.top: header.bottom
        anchors.topMargin: 10
        anchors.bottom: parent.bottom
        width: parent.width

        Flickable {
            id: flick
            anchors.fill: parent
            anchors.rightMargin: root.scrolls ? 10 : 0
            contentHeight: col.implicitHeight
            interactive: root.scrolls && contentHeight > height
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: col
                x: 4
                width: flick.width - 8
                spacing: 6
            }
        }

        // scroll indicator, as in the Keybinds list
        Rectangle {
            anchors.right: parent.right
            width: 3
            radius: 1.5
            color: Theme.muted
            visible: root.scrolls && flick.contentHeight > flick.height
            height: Math.max(20, flick.height * flick.height / Math.max(1, flick.contentHeight))
            y: (flick.height - height) * (flick.contentY / Math.max(1, flick.contentHeight - flick.height))
        }
    }
}
