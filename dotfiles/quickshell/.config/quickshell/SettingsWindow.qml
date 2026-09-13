// Neutrino - Quickshell
// ~/.config/quickshell/SettingsWindow.qml
//
// Settings: a sidebar of sections and a pane showing one of them. Changes
// apply as they're made -- there is no Save -- and each page writes straight
// to the thing it controls (mimeapps.list, hyprland.lua, hypridle.conf,
// pipewire, swaync) rather than to a store of its own. Appearance stays in
// the Control Centre, where it already lives; its entry here opens it.
//
// Its own FloatingWindow rather than a CentredWindow: that one is a single
// content-sized Column, and a fixed-size sidebar + pane doesn't fit it. The
// chrome is the same WindowChrome.qml.
//
// No memory: every open starts on File Types, and the page is a Loader that
// only exists while the window is visible, so nothing a page read or ran
// survives a close -- and nothing runs at all while Settings is shut.
//
// Floating and centring come from the "quickshell-windows" rule in
// hyprland.lua, as for System and Keybinds.

import Quickshell
import QtQuick

FloatingWindow {
    id: root

    readonly property string defaultPage: "filetypes"
    property string currentPage: defaultPage

    readonly property int sidebarWidth: 190
    // Keybinds' list is laid out for 720; the page frame adds its margin
    readonly property int paneWidth: 740
    readonly property int paneHeight: 600

    // The Appearance entry: shell.qml opens the Control Centre on that page,
    // on the focused screen, since the Control Centre is per screen and
    // this window isn't.
    signal appearanceRequested()

    visible: false
    title: "Settings"
    color: "transparent"

    implicitWidth: 16 + sidebarWidth + 12 + 1 + 12 + paneWidth + 16
    implicitHeight: chrome.contentY + paneHeight + 16

    function open() { visible = true }
    function close() { visible = false }

    // the compositor closing it has to clear visible, or the next open()
    // would be a no-op
    onClosed: visible = false
    onVisibleChanged: if (visible) {
        currentPage = defaultPage
        chrome.keySink.forceActiveFocus()
    }

    readonly property var pages: [
        { id: "filetypes",     label: "File Types",    icon: "󰈔", source: "SettingsPageFileTypes.qml" },
        { id: "appearance",    label: "Appearance",    icon: "󰏘", external: true },
        { id: "input",         label: "Input",         icon: "󰌌", source: "SettingsPageInput.qml" },
        { id: "audio",         label: "Audio",         icon: "󰕾", source: "SettingsPageAudio.qml" },
        { id: "display",       label: "Display",       icon: "󰍹", source: "SettingsPageDisplay.qml" },
        { id: "power",         label: "Power & Idle",  icon: "󰂄", source: "SettingsPagePower.qml" },
        { id: "notifications", label: "Notifications", icon: "󰂚", source: "SettingsPageNotifications.qml" },
        { id: "shell",         label: "Terminal",      icon: "󰆍", source: "SettingsPageShell.qml" },
        { id: "keybinds",      label: "Keybinds",      icon: "󰘳", source: "SettingsPageKeybinds.qml" },
    ]

    function select(page) {
        if (page.external) {
            close()
            appearanceRequested()
            return
        }
        currentPage = page.id
        // a page's field may have had focus; give Escape back to the window
        chrome.keySink.forceActiveFocus()
    }

    WindowChrome {
        id: chrome
        window: root
        heading: "SETTINGS"
    }

    // --- sidebar -----------------------------------------------------------

    Column {
        id: sidebar
        x: 16
        y: chrome.contentY
        width: root.sidebarWidth
        spacing: 2

        Repeater {
            model: root.pages

            SettingsNavRow {
                required property var modelData
                icon: modelData.icon
                label: modelData.label
                external: !!modelData.external
                selected: root.currentPage === modelData.id
                onClicked: root.select(modelData)
            }
        }
    }

    Rectangle {
        id: rule
        anchors.left: sidebar.right
        anchors.leftMargin: 12
        y: chrome.contentY
        width: 1
        height: root.paneHeight
        color: Theme.border
    }

    // --- pane --------------------------------------------------------------

    Loader {
        id: pane
        anchors.left: rule.right
        anchors.leftMargin: 12
        y: chrome.contentY
        width: root.paneWidth
        height: root.paneHeight
        active: root.visible
        source: {
            var p = root.pages.find(p => p.id === root.currentPage)
            return p && p.source ? p.source : ""
        }
    }
}
