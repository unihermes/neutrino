// Neutrino - Quickshell
// ~/.config/quickshell/BarWidgetList.qml
//
// The Bar Widgets page's list: every bar module with a drag handle and a
// show/hide switch, grouped under LEFT / CENTRE / RIGHT headers.
//
// It's one list, not three. The section headers are rows in it that never
// move, so a module dragged past a header simply ends up on the other side
// of it -- which is what moving it into another section means. Dragging
// between three separate lists would need the row to leave one view and be
// adopted by another mid-drag. Where a module sits relative to the headers
// is written back as the layout.
//
// The list is a ListModel copy of the saved layout rather than bound to it.
// ListModel.move() keeps the dragged row's delegate alive, so the pointer
// stays attached to the row while it changes slots; rebuilding from a bound
// array on every step would destroy the row mid-drag. Each move is written
// straight back to Settings, which is what makes the bar follow live.

import QtQuick

Column {
    id: root

    // key -> { label, icon }
    property var meta: ({})

    width: parent ? parent.width : 0

    readonly property int rowHeight: 28
    readonly property var sectionTitles: ({ left: "LEFT", centre: "CENTRE", right: "RIGHT" })

    // bumped on every change to the rows, so per-row bindings that look at
    // their neighbours (the "empty" hint) re-evaluate
    property int revision: 0

    function refill() {
        widgetModel.clear()
        var l = Settings.widgetLayout()
        for (var i = 0; i < Settings.widgetSections.length; i++) {
            var sec = Settings.widgetSections[i]
            widgetModel.append({ key: sec, header: true })
            for (var j = 0; j < l[sec].length; j++)
                widgetModel.append({ key: l[sec][j], header: false })
        }
        revision++
    }

    // one slot move, as a drag step makes it
    function moveRow(from, to) {
        // index 0 is the LEFT header; nothing may go above it
        to = Math.max(1, to)
        if (from === to || from < 1 || from >= widgetModel.count || to >= widgetModel.count) return
        if (widgetModel.get(from).header) return
        widgetModel.move(from, to, 1)
        revision++
        commit()
    }

    // walk the rows, assigning each module to the header above it
    function commit() {
        var layout = { left: [], centre: [], right: [] }
        var sec = "left"
        for (var i = 0; i < widgetModel.count; i++) {
            var r = widgetModel.get(i)
            if (r.header) sec = r.key
            else layout[sec].push(r.key)
        }
        Settings.setWidgetLayout(layout)
    }

    // the section a row sits in: the key of the nearest header above it
    function sectionAt(index) {
        for (var i = index; i >= 0; i--) {
            var r = widgetModel.get(i)
            if (r && r.header) return r.key
        }
        return "left"
    }

    // whether the section headed at `index` has no modules under it
    function sectionEmpty(index) {
        return index + 1 >= widgetModel.count || widgetModel.get(index + 1).header
    }

    Component.onCompleted: refill()

    // not `model`: inside a ListView and its delegates that name is taken
    ListModel { id: widgetModel }

    ListView {
        id: list
        width: parent.width
        height: widgetModel.count * root.rowHeight
        interactive: false
        model: widgetModel

        // the rows being pushed aside slide rather than jump
        displaced: Transition {
            NumberAnimation { properties: "y"; duration: Theme.dur(120); easing.type: Easing.OutCubic }
        }

        delegate: Item {
            id: row
            required property string key
            required property bool header
            required property int index
            readonly property var info: root.meta[key] || { label: key, icon: "" }
            readonly property bool locked: Settings.lockedWidgets.indexOf(key) !== -1
            readonly property bool dragging: grip.pressed

            width: list.width
            height: root.rowHeight
            z: dragging ? 1 : 0

            // --- section header ---
            Row {
                visible: row.header
                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 5
                spacing: 8

                Text {
                    text: root.sectionTitles[row.key] || row.key
                    color: Theme.subtext
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontSmall
                    font.bold: true
                    font.letterSpacing: 1
                }

                Text {
                    visible: root.revision >= 0 && row.header && root.sectionEmpty(row.index)
                    text: "empty, drag a module here"
                    color: Theme.muted
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontSmall
                }
            }

            // --- module row ---
            Item {
                visible: !row.header
                anchors.fill: parent

                // lifted look while held, so it's clear which row is moving
                Rectangle {
                    anchors.fill: parent
                    anchors.leftMargin: -4
                    anchors.rightMargin: -4
                    radius: Theme.radiusInner
                    color: row.dragging ? Theme.overlay : "transparent"
                    border.width: row.dragging ? 1 : 0
                    border.color: Theme.muted
                }

                Item {
                    id: handle
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: parent.height

                    Text {
                        anchors.centerIn: parent
                        text: "󰇝"
                        color: row.dragging ? Theme.bright
                            : grip.containsMouse ? Theme.text : Theme.muted
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontIconSize
                    }

                    MouseArea {
                        id: grip
                        anchors.fill: parent
                        enabled: !row.header
                        hoverEnabled: true
                        preventStealing: true
                        cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                        onPositionChanged: mouse => {
                            if (!pressed) return
                            var p = mapToItem(list, mouse.x, mouse.y)
                            var to = Math.max(0, Math.min(widgetModel.count - 1,
                                Math.floor(p.y / root.rowHeight)))
                            root.moveRow(row.index, to)
                        }
                    }
                }

                // Pin, on centre rows only: locks that module to the exact
                // middle of the bar. Clicking the pinned one unpins it.
                Item {
                    id: pin
                    readonly property bool inCentre: root.revision >= 0 && !row.header
                        && root.sectionAt(row.index) === "centre"
                    readonly property bool pinned: Settings.centreAnchor === row.key
                    visible: inCentre
                    z: 2
                    anchors.right: parent.right
                    // clears the FlyoutAction's switch, which sits flush right
                    anchors.rightMargin: 26 + 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 18
                    height: 18

                    Text {
                        anchors.centerIn: parent
                        text: pin.pinned ? "󰐃" : "󰤰"
                        color: pin.pinned ? Theme.bright
                            : pinMouse.containsMouse ? Theme.text : Theme.muted
                        font.family: Theme.fontIcon
                        font.pixelSize: Theme.fontIconSize
                    }

                    MouseArea {
                        id: pinMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Settings.setCentreAnchor(pin.pinned ? "" : row.key)
                    }
                }

                FlyoutAction {
                    anchors.left: handle.right
                    anchors.leftMargin: 4
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    icon: row.info.icon
                    label: row.info.label
                    checkable: !row.locked
                    checked: Settings.widgetVisible(row.key)
                    // the locked row says why it has no switch, rather than
                    // looking like a broken one
                    trailingIcon: row.locked ? "󰌾" : ""
                    onActivated: if (!row.locked)
                        Settings.setWidgetVisible(row.key, !Settings.widgetVisible(row.key))
                }
            }
        }
    }
}
