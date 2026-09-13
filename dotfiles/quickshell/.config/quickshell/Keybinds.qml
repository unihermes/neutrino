// Neutrino - Quickshell
// ~/.config/quickshell/Keybinds.qml
//
// Keybinds as its own window. The editor is KeybindsBody.qml, which the
// Settings window's Keybinds page hosts as well.

import QtQuick

CentredWindow {
    id: root

    heading: "KEYBINDS"
    contentWidth: 720

    KeybindsBody {
        active: root.visible
        onCloseRequested: root.close()
    }
}
