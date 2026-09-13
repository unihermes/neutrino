// Neutrino - Quickshell
// ~/.config/quickshell/SettingsPageAudio.qml
//
// Output and input devices: which one is the default, its volume, mute.
//
// Straight onto Pipewire through Quickshell's service, the same one the bar's
// volume module reads, so the two always agree. Nothing to persist:
// wireplumber remembers the chosen default and each device's volume itself.

import Quickshell.Services.Pipewire
import QtQuick

SettingsPage {
    id: page

    title: "Audio"
    description: "Default output and input, and their levels. Wireplumber remembers these across restarts."

    readonly property var devices: Pipewire.nodes.values.filter(n => n.audio && !n.isStream)
    readonly property var sinks: devices.filter(n => n.isSink)
    readonly property var sources: devices.filter(n => !n.isSink)

    // audio.volume / audio.muted stay invalid until a node is tracked
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource]
    }

    function nodeName(n) {
        return n ? (n.description || n.nickname || n.name) : ""
    }

    component Level: SettingsField {
        id: lvl
        property var node: null
        readonly property bool ready: node !== null && node.ready && node.audio !== null

        label: "Volume"
        hint: ready ? page.nodeName(node) : "No device"

        Row {
            anchors.right: parent.right
            spacing: 10

            Slider {
                width: 220
                anchors.verticalCenter: parent.verticalCenter
                value: lvl.ready ? lvl.node.audio.volume * 100 : 0
                onMoved: v => { if (lvl.ready) lvl.node.audio.volume = v / 100 }
            }
            Text {
                width: Theme.fs(40)
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                text: lvl.ready ? Math.round(lvl.node.audio.volume * 100) + "%" : "--"
                color: Theme.bright
                font.family: Theme.fontText
                font.pixelSize: Theme.fontBody
            }
            FlyoutChip {
                anchors.verticalCenter: parent.verticalCenter
                text: lvl.ready && lvl.node.audio.muted ? "Muted" : "Mute"
                selected: lvl.ready && lvl.node.audio.muted
                enabled: lvl.ready
                onClicked: lvl.node.audio.muted = !lvl.node.audio.muted
            }
        }
    }

    component DeviceList: Column {
        id: dl
        property var nodes: []
        property var current: null
        signal picked(var node)

        width: parent.width
        spacing: 2

        Repeater {
            model: dl.nodes
            FlyoutRow {
                required property var modelData
                label: page.nodeName(modelData)
                highlighted: dl.current === modelData
                trailing: highlighted ? "󰄬" : ""
                onActivated: if (!highlighted) dl.picked(modelData)
            }
        }

        Text {
            visible: dl.nodes.length === 0
            text: "None found"
            color: Theme.subtext
            font.family: Theme.fontText
            font.pixelSize: Theme.fontBody
        }
    }

    FlyoutHeading { text: "OUTPUT" }

    Level { node: Pipewire.defaultAudioSink }

    DeviceList {
        nodes: page.sinks
        current: Pipewire.defaultAudioSink
        onPicked: node => {
            Pipewire.preferredDefaultAudioSink = node
            page.say("Output: " + page.nodeName(node), false)
        }
    }

    Item { width: 1; height: 6 }
    FlyoutHeading { text: "INPUT" }

    Level { node: Pipewire.defaultAudioSource }

    DeviceList {
        nodes: page.sources
        current: Pipewire.defaultAudioSource
        onPicked: node => {
            Pipewire.preferredDefaultAudioSource = node
            page.say("Input: " + page.nodeName(node), false)
        }
    }
}
