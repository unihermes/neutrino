// Neutrino - Quickshell
// ~/.config/quickshell/SettingsPageInput.qml
//
// Keyboard, mouse and touchpad: the `input = { }` table in hyprland.lua.
//
// Every change is written to the file and followed by a config reload, which
// is what applies it -- there's no separate live path. `hyprctl keyword`
// refuses to run under the Lua config, and a reload already re-reads every
// input option, so writing first is both the only way that sticks and
// effectively instant. The writes go through HyprLuaWrite, so each one is
// syntax-checked, backed up, and checked against `hyprctl configerrors`.
//
// Values are read from the file, not from Hyprland: the page shows what's
// configured, which is what survives a restart. A key the file doesn't set
// shows Hyprland's default and is added on first change.

import Quickshell.Io
import QtQuick
import "HyprTables.js" as HyprTables

SettingsPage {
    id: page

    title: "Input"
    description: "Keyboard, mouse and touchpad, from the input table in hyprland.lua. Each change is saved and Hyprland reloads."

    property var conf: ({ found: false, fields: {}, touchpad: {} })

    // Hyprland's own defaults, for keys the file leaves out
    readonly property var defaults: ({
        kb_layout: "us", kb_variant: "", kb_options: "", repeat_rate: 25, repeat_delay: 600, numlock_by_default: false,
        follow_mouse: 1, sensitivity: 0, accel_profile: "", left_handed: false,
        natural_scroll: false, disable_while_typing: true, scroll_factor: 1, tap_to_click: true,
        clickfinger_behavior: false, drag_lock: false, middle_button_emulation: false,
    })

    function field(sub, key) {
        var table = sub === "touchpad" ? conf.touchpad : conf.fields
        var f = table[key]
        return f === undefined ? { editable: true, value: defaults[key], unset: true } : f
    }

    function value(sub, key) { return field(sub, key).value }

    function set(sub, key, v, label) {
        writer.patch(src => HyprTables.setInput(src, sub, key, v),
            label + " set to " + (typeof v === "boolean" ? (v ? "on" : "off") : (v === "" ? "none" : v)),
            (sub ? sub + "." : "") + key + " isn't a plain value in hyprland.lua, edit it by hand")
    }

    function reread() {
        luaFile.reload()
        luaFile.waitForJob()
        conf = HyprTables.readInput(luaFile.text())
        if (!conf.found) say("No input = { } table inside hl.config in hyprland.lua", true)
    }

    Component.onCompleted: reread()

    FileView {
        id: luaFile
        path: writer.confPath
        blockLoading: true
        watchChanges: true
        printErrors: false
        onFileChanged: if (!writer.busy) page.reread()
    }

    HyprLuaWrite {
        id: writer
        visible: false
        onPatched: (ok, message) => {
            page.say(message, !ok)
            page.reread()
        }
    }

    // --- pieces --------------------------------------------------------------

    component Choice: Row {
        id: choice
        property string sub: ""
        property string key: ""
        property string label: ""
        // [{ text, value }]
        property var options: []
        readonly property var current: page.value(sub, key)

        anchors.right: parent.right
        spacing: 4

        Repeater {
            model: choice.options
            FlyoutChip {
                required property var modelData
                text: modelData.text
                selected: choice.current === modelData.value
                enabled: page.field(choice.sub, choice.key).editable
                onClicked: if (!selected) page.set(choice.sub, choice.key, modelData.value, choice.label)
            }
        }
    }

    component Toggle: SettingsField {
        id: tg
        property string sub: ""
        property string key: ""

        Choice {
            sub: tg.sub
            key: tg.key
            label: tg.label
            options: [{ text: "Off", value: false }, { text: "On", value: true }]
        }
    }

    // A stepper over a decimal range: FlyoutStepper is integer-only, so it
    // steps in units of `step` and this converts at the edges.
    component Decimal: SettingsField {
        id: dec
        property string sub: ""
        property string key: ""
        property real step: 0.1
        property real min: 0
        property real max: 1
        property int digits: 1
        readonly property real current: Number(page.value(sub, key))

        Item {
            anchors.right: parent.right
            width: 140
            height: Theme.fs(24)

            FlyoutStepper {
                width: parent.width
                value: Math.round(dec.current / dec.step)
                minimum: Math.round(dec.min / dec.step)
                maximum: Math.round(dec.max / dec.step)
                displayValue: dec.current.toFixed(dec.digits)
                valueWidth: 44
                onStepped: delta => {
                    var v = Math.round((dec.current + delta * dec.step) * 1000) / 1000
                    page.set(dec.sub, dec.key, Math.max(dec.min, Math.min(dec.max, v)), dec.label)
                }
            }
        }
    }

    component Integer: SettingsField {
        id: int_
        property string sub: ""
        property string key: ""
        property int step: 1
        property int min: 0
        property int max: 100
        property string suffix: ""

        FlyoutStepper {
            anchors.right: parent.right
            width: 160
            value: Number(page.value(int_.sub, int_.key))
            minimum: int_.min
            maximum: int_.max
            suffix: int_.suffix
            valueWidth: 56
            onStepped: delta => page.set(int_.sub, int_.key,
                Math.max(int_.min, Math.min(int_.max, value + delta * int_.step)), int_.label)
        }
    }

    component Text_: SettingsField {
        id: tx
        property string sub: ""
        property string key: ""
        property string placeholder: ""

        FlyoutInput {
            id: input
            anchors.right: parent.right
            width: 220
            echoPassword: false
            placeholder: tx.placeholder
            text: String(page.value(tx.sub, tx.key))
            onAccepted: if (text.trim() !== String(page.value(tx.sub, tx.key)))
                page.set(tx.sub, tx.key, text.trim(), tx.label)
            onEscapePressed: text = String(page.value(tx.sub, tx.key))

            // typing breaks the binding; put the file's value back after
            // every re-read, which follows every write
            Connections {
                target: page
                function onConfChanged() { input.text = String(page.value(tx.sub, tx.key)) }
            }
        }
    }

    // --- layout --------------------------------------------------------------

    FlyoutHeading { text: "KEYBOARD" }

    Text_ {
        key: "kb_layout"
        label: "Layout"
        hint: "xkb layouts, comma-separated: us,de. Enter to apply"
        placeholder: "us"
    }
    Text_ {
        key: "kb_variant"
        label: "Variant"
        hint: "per layout, e.g. colemak. Enter to apply"
        placeholder: "none"
    }
    Text_ {
        key: "kb_options"
        label: "Options"
        hint: "xkb options, e.g. caps:escape. Enter to apply"
        placeholder: "none"
    }
    Integer {
        key: "repeat_rate"
        label: "Repeat rate"
        hint: "repeats per second while a key is held"
        min: 5; max: 80; step: 5
        suffix: "/s"
    }
    Integer {
        key: "repeat_delay"
        label: "Repeat delay"
        hint: "how long a key is held before it repeats"
        min: 100; max: 1500; step: 50
        suffix: "ms"
    }
    Toggle {
        key: "numlock_by_default"
        label: "Num Lock on at login"
    }

    Item { width: 1; height: 6 }
    FlyoutHeading { text: "MOUSE" }

    Decimal {
        key: "sensitivity"
        label: "Sensitivity"
        hint: "-1 to 1, added to the device's own speed"
        min: -1; max: 1; step: 0.1
    }
    SettingsField {
        label: "Acceleration"
        hint: "flat moves the pointer exactly as far as the hand does"
        Choice {
            key: "accel_profile"
            label: "Acceleration"
            options: [{ text: "Default", value: "" }, { text: "Adaptive", value: "adaptive" }, { text: "Flat", value: "flat" }]
        }
    }
    SettingsField {
        label: "Focus follows mouse"
        hint: "0 click to focus · 1 always · 2 cursor only · 3 detached"
        Choice {
            key: "follow_mouse"
            label: "Focus follows mouse"
            options: [0, 1, 2, 3].map(n => ({ text: String(n), value: n }))
        }
    }
    Toggle {
        key: "left_handed"
        label: "Left-handed"
        hint: "swaps the primary and secondary buttons"
    }

    Item { width: 1; height: 6 }
    FlyoutHeading { text: "TOUCHPAD" }

    Toggle {
        sub: "touchpad"; key: "tap_to_click"
        label: "Tap to click"
    }
    Toggle {
        sub: "touchpad"; key: "natural_scroll"
        label: "Natural scrolling"
        hint: "content follows the fingers, as on a phone"
    }
    Toggle {
        sub: "touchpad"; key: "disable_while_typing"
        label: "Disable while typing"
    }
    Decimal {
        sub: "touchpad"; key: "scroll_factor"
        label: "Scroll speed"
        hint: "multiplier on two-finger scroll distance"
        min: 0.1; max: 3; step: 0.1
    }
    Toggle {
        sub: "touchpad"; key: "clickfinger_behavior"
        label: "Click by finger count"
        hint: "two-finger press is right click, three is middle"
    }
    Toggle {
        sub: "touchpad"; key: "drag_lock"
        label: "Drag lock"
        hint: "lifting a finger mid-drag doesn't drop what's held"
    }
    Toggle {
        sub: "touchpad"; key: "middle_button_emulation"
        label: "Middle-click emulation"
        hint: "left and right pressed together"
    }
}
