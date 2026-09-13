// Neutrino - Quickshell
// ~/.config/quickshell/Privacy.qml
//
// Which apps are recording the microphone, the camera, or the screen right
// now, for a bar indicator that only appears while one is.
//
// Read from Pipewire's node list. An app capturing audio shows up as an
// audio *input stream* and an app capturing video as a video input stream;
// a screen share is the source node xdg-desktop-portal-hyprland creates,
// named xdph-streaming-*. The node type flags are available without binding
// every node, which is what makes watching them all cheap.
//
// Limit: an app that opens /dev/video* directly (older Chromium builds do)
// never goes through Pipewire, so its camera use isn't seen.

pragma Singleton

import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

Singleton {
    id: root

    // The shell's own capture: cava listens to the output to draw the
    // visualizer, and that must not light the microphone indicator.
    readonly property var ignored: ["cava"]

    function scan() {
        var mic = [], cam = [], screen = []
        var nodes = Pipewire.nodes.values
        for (var i = 0; i < nodes.length; i++) {
            var n = nodes[i]
            var name = n.name || ""
            if (ignored.indexOf(name) !== -1) continue
            var label = n.description || n.nickname || name
            if (name.startsWith("xdph-streaming")) screen.push("Screen share")
            else if (n.type === PwNodeType.AudioInStream) mic.push(label)
            else if (n.type === (PwNodeType.Video | PwNodeType.Stream | PwNodeType.Source)) cam.push(label)
        }
        return { mic: mic, camera: cam, screen: screen }
    }

    readonly property var state: scan()
    readonly property bool mic: state.mic.length > 0
    readonly property bool camera: state.camera.length > 0
    readonly property bool screen: state.screen.length > 0
    readonly property bool active: mic || camera || screen
}
