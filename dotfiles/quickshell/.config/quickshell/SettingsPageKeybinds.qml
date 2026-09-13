// Neutrino - Quickshell
// ~/.config/quickshell/SettingsPageKeybinds.qml
//
// The Keybinds editor, embedded. Same component as the standalone Keybinds
// window, so the two can't drift; it keeps its own list scrolling, and its
// own status line in place of the page's.

import QtQuick

SettingsPage {
    id: page

    title: "Keybinds"
    description: "Every hl.bind() in hyprland.lua. Saving checks the Lua, backs the file up and reloads Hyprland."
    scrolls: false

    KeybindsBody {
        // created when the page is shown, so it's live for its whole life
        active: true
        standalone: false
        // toolbar, spacing, status line, spacing -- the rest is the list
        bodyHeight: page.bodyHeight - Theme.fs(26) - Theme.fs(16) - 12
    }
}
