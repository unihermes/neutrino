// Neutrino - Quickshell
// ~/.config/quickshell/CentredWindow.qml
//
// A standalone window opened from the Control Centre (System, Keybinds): a
// real toplevel rather than a layer-shell flyout, so it can be focused,
// moved, alt-tabbed to and left open while you work. The flyouts close on
// click-off; these deliberately don't. The chrome is WindowChrome.qml.
//
// Floating and centring are Hyprland's job, not this file's -- see the
// "quickshell-windows" rule in hyprland.lua. Without it the monocle rule
// maximizes these like any other tiled window.

import Quickshell
import QtQuick

FloatingWindow {
    id: root

    property string heading: ""
    // content width; the window's height follows whatever is put in it
    property int contentWidth: 380
    // data, not children: a window's content includes non-visual objects
    // (FileViews, Timers, Processes), and children only accepts Items. The
    // Column still lays out just the Items among them.
    default property alias content: body.data

    // Closed until something calls open(). Each open maps a fresh toplevel,
    // so Hyprland's rule re-centres it on the focused monitor every time.
    visible: false
    title: heading.charAt(0) + heading.slice(1).toLowerCase()
    color: "transparent"

    implicitWidth: contentWidth + 2 * 16
    implicitHeight: body.implicitHeight + chrome.contentY + 16

    function open() { visible = true }
    function close() { visible = false }

    // the compositor closing it (SUPER+Q, a click on nothing) comes through
    // here, and has to clear visible or the next open() would be a no-op
    onClosed: visible = false

    WindowChrome {
        id: chrome
        window: root
        heading: root.heading
    }

    Column {
        id: body
        x: 16
        y: chrome.contentY
        width: root.contentWidth
        spacing: 6
    }
}
