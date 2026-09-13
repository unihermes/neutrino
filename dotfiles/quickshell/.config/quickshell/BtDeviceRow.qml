// Neutrino - Quickshell
// ~/.config/quickshell/BtDeviceRow.qml
//
// One Bluetooth device in the flyout. Extends FlyoutRow rather than wrapping
// one so it still behaves like a plain row inside the flyout's Column --
// a wrapper would have to forward width and height by hand.
//
// Shared by the saved and nearby sections, which differ only in which
// devices they feed it.

import QtQuick

FlyoutRow {
    id: root

    required property var device

    // deviceName is the advertised name; `name` is BlueZ's Alias, which it
    // fills with a dashed copy of the MAC when no name is known, so it is
    // never empty and can't be used to detect "nameless".
    label: device.deviceName !== "" ? device.deviceName
        : (device.name !== "" ? device.name : device.address)

    trailing: {
        if (device.pairing) return "pairing"
        // BlueZ reports battery as a 0..1 fraction despite the name, the
        // same as UPower -- rounding it directly shows a full headset as 1%
        if (device.connected && device.batteryAvailable)
            return Math.round(device.battery * 100) + "%"
        if (device.connected) return ""
        if (device.paired) return ""
        return "new"
    }

    highlighted: device.connected
    enabled: !device.pairing

    onActivated: {
        if (device.connected) {
            device.disconnect()
        } else if (device.paired) {
            device.connect()
        } else {
            // Native pair() works because bt-agent.service keeps a pairing
            // agent registered -- without one BlueZ fails this with "No
            // agent available for request type 2" and the row silently
            // reverts to its previous state.
            device.pair()
        }
    }

    Connections {
        target: root.device
        function onPairedChanged() {
            if (!root.device.paired) return
            // a device that isn't trusted is not allowed to reconnect itself
            // when you power it back on
            root.device.trusted = true
            // pair() returns once the bond exists, which is not the same as
            // the device being usable -- headphones bond and then sit idle
            // until something connects them
            if (!root.device.connected) root.device.connect()
        }
    }
}
