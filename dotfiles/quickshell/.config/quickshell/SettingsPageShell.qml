// Neutrino - Quickshell
// ~/.config/quickshell/SettingsPageShell.qml
//
// Alacritty's look, and the aliases in ~/.bashrc.
//
// Two different kinds of instant, and the page says which is which.
// Alacritty watches its own config, so a change there shows in every open
// terminal the moment it's written. .bashrc is only read when a shell
// starts, so alias edits apply to new terminals -- the ones already open
// keep what they had until `source ~/.bashrc`.
//
// Both are line edits, like the other pages: a TOML key's value inside its
// [table], or one `alias name='...'` line. Everything else in either file is
// left as it was.

import Quickshell
import Quickshell.Io
import QtQuick

SettingsPage {
    id: page

    title: "Terminal"
    description: "Alacritty applies changes to open windows as they're saved. Aliases in ~/.bashrc apply to new terminals."

    readonly property string home: Quickshell.env("HOME")
    readonly property string alacrittyPath:
        (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/alacritty/alacritty.toml"
    readonly property string bashrcPath: home + "/.bashrc"

    // --- alacritty -----------------------------------------------------------

    // "table.key" -> raw TOML value text
    property var toml: ({})

    // Line-based: tracks the current [table] header and reads `key = value`
    // lines under it. Inline tables and arrays aren't looked into -- nothing
    // this page sets lives in one.
    function parseToml(text) {
        var out = {}, table = ""
        text.split("\n").forEach(line => {
            var l = line.replace(/\s+#.*$/, "").trim()
            var m
            if ((m = /^\[([^\]]+)\]$/.exec(l))) table = m[1].trim()
            else if ((m = /^([A-Za-z0-9_-]+)\s*=\s*(.+)$/.exec(l))) out[(table ? table + "." : "") + m[1]] = m[2]
        })
        return out
    }

    function tomlValue(path, fallback) {
        var raw = toml[path]
        if (raw === undefined) return fallback
        if (/^".*"$/.test(raw)) return raw.slice(1, -1)
        if (raw === "true" || raw === "false") return raw === "true"
        var n = Number(raw)
        return isNaN(n) ? raw : n
    }

    function tomlLiteral(v) {
        if (typeof v === "boolean") return v ? "true" : "false"
        if (typeof v === "number") return Number.isInteger(v) ? v.toFixed(1) : String(Math.round(v * 100) / 100)
        return JSON.stringify(v)
    }

    // Set key in [table], replacing its line, or adding it under the table
    // header (and the header at the end of the file if there isn't one).
    function setToml(table, key, value, message) {
        alacrittyFile.reload()
        alacrittyFile.waitForJob()
        var lines = alacrittyFile.text().split("\n")
        var cur = "", headerAt = -1, lastInTable = -1
        for (var i = 0; i < lines.length; i++) {
            var l = lines[i].trim()
            var m = /^\[([^\]]+)\]/.exec(l)
            if (m) { cur = m[1].trim(); if (cur === table) { headerAt = i; lastInTable = i } continue }
            if (cur !== table) continue
            if (l !== "" && !l.startsWith("#")) lastInTable = i
            var km = new RegExp("^(\\s*" + key + "\\s*=\\s*)([^#]*?)(\\s*(#.*)?)$").exec(lines[i])
            if (km) {
                lines[i] = km[1] + tomlLiteral(value) + km[3]
                return writeFile(alacrittyPath, lines.join("\n"), message, false)
            }
        }
        var entry = key + " = " + tomlLiteral(value)
        if (headerAt < 0) lines.push("", "[" + table + "]", entry)
        else lines.splice(lastInTable + 1, 0, entry)
        writeFile(alacrittyPath, lines.join("\n"), message, false)
    }

    FileView {
        id: alacrittyFile
        path: page.alacrittyPath
        blockLoading: true
        printErrors: false
    }

    // --- aliases -------------------------------------------------------------

    // [{ name, value, line }]
    property var aliases: []

    function parseAliases(text) {
        var out = []
        text.split("\n").forEach((line, i) => {
            var m = /^\s*alias\s+([A-Za-z0-9_.:-]+)=(?:'([^']*)'|"((?:[^"\\]|\\.)*)"|(\S+))\s*$/.exec(line)
            if (m) out.push({ name: m[1], value: m[2] !== undefined ? m[2] : m[3] !== undefined ? m[3] : m[4], line: i })
        })
        return out
    }

    // single quotes can't hold a single quote: close, escape one, reopen
    function shQuote(s) {
        return "'" + s.replace(/'/g, "'\\''") + "'"
    }

    function addAlias(name, value) {
        name = name.trim()
        if (!/^[A-Za-z0-9_.:-]+$/.test(name)) { say("An alias name is letters, digits and _ . : - only", true); return false }
        if (value.trim() === "") { say("The alias needs a command", true); return false }
        bashrcFile.reload()
        bashrcFile.waitForJob()
        var text = bashrcFile.text()
        var lines = text.split("\n")
        var current = parseAliases(text)
        var line = "alias " + name + "=" + shQuote(value.trim())
        var existing = current.find(a => a.name === name)
        if (existing) {
            lines[existing.line] = line
        } else if (current.length > 0) {
            lines.splice(current[current.length - 1].line + 1, 0, line)
        } else {
            // before a trailing blank line, so the file still ends the same way
            var at = lines.length && lines[lines.length - 1] === "" ? lines.length - 1 : lines.length
            lines.splice(at, 0, line)
        }
        writeFile(bashrcPath, lines.join("\n"), (existing ? "Changed " : "Added ") + name + ", in new terminals", true)
        return true
    }

    function removeAlias(a) {
        bashrcFile.reload()
        bashrcFile.waitForJob()
        var lines = bashrcFile.text().split("\n")
        var fresh = parseAliases(lines.join("\n")).find(x => x.name === a.name && x.line === a.line)
        if (!fresh) { say("~/.bashrc changed on disk; nothing removed", true); reread(); return }
        lines.splice(a.line, 1)
        writeFile(bashrcPath, lines.join("\n"), "Removed " + a.name + ", in new terminals", true)
    }

    FileView {
        id: bashrcFile
        path: page.bashrcPath
        blockLoading: true
        printErrors: false
    }

    // --- shared --------------------------------------------------------------

    // `cat >` rather than a rename: ~/.bashrc is a stow symlink into the
    // repo, and a rename would replace the link with a plain file.
    // .bashrc edits are checked with `bash -n` first.
    function writeFile(path, text, message, checkBash) {
        if (writeProc.running) { say("Still writing the last change", true); return }
        writeProc.message = message
        writeProc.command = ["sh", "-c", `
            exec 2>&1
            printf %s "$2" > "$1.new" || { echo write; exit; }
            if [ "$3" = 1 ]; then
                out=$(bash -n "$1.new" 2>&1) || { echo syntax; printf "%s\\n" "$out"; rm -f -- "$1.new"; exit; }
            fi
            cat -- "$1.new" > "$1" && rm -f -- "$1.new" || { echo write; exit; }
            echo ok`, "sh", path, text, checkBash ? "1" : "0"]
        writeProc.running = true
    }

    Process {
        id: writeProc
        property string message: ""
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.trim().split("\n")
                var status = lines.shift()
                if (status === "ok") page.say(writeProc.message, false)
                else if (status === "syntax") page.say("Not written, bash -n says: " + (lines[0] || "syntax error").replace(/^.*?: line/, "line"), true)
                else page.say("Couldn't write the file", true)
                page.reread()
            }
        }
    }

    function reread() {
        alacrittyFile.reload()
        alacrittyFile.waitForJob()
        toml = parseToml(alacrittyFile.text())
        bashrcFile.reload()
        bashrcFile.waitForJob()
        aliases = parseAliases(bashrcFile.text())
    }

    Component.onCompleted: reread()

    // --- layout --------------------------------------------------------------

    FlyoutHeading { text: "ALACRITTY" }

    SettingsField {
        label: "Font size"
        hint: "points"
        FlyoutStepper {
            anchors.right: parent.right
            width: 170
            readonly property real current: Number(page.tomlValue("font.size", 11.25))
            value: Math.round(current * 2)
            minimum: 12
            maximum: 64
            valueWidth: 56
            displayValue: current.toFixed(1)
            onStepped: delta => page.setToml("font", "size", (value + delta) / 2, "Font size " + ((value + delta) / 2).toFixed(1))
        }
    }

    SettingsField {
        label: "Opacity"
        hint: "of the background; text stays solid"
        FlyoutStepper {
            anchors.right: parent.right
            width: 170
            readonly property real current: Number(page.tomlValue("window.opacity", 1))
            value: Math.round(current * 20)
            minimum: 6
            maximum: 20
            valueWidth: 56
            displayValue: Math.round(current * 100) + "%"
            onStepped: delta => page.setToml("window", "opacity", (value + delta) / 20, "Opacity " + (value + delta) * 5 + "%")
        }
    }

    SettingsField {
        label: "Cursor"
        hint: "shape, and whether it blinks"

        Row {
            anchors.right: parent.right
            spacing: 10

            // style = { shape = "Beam", blinking = "On" } is an inline
            // table, so it's read by pattern rather than parsed
            readonly property string styleRaw: String(page.toml["cursor.style"] || "")
            readonly property string shape: (/shape\s*=\s*"(\w+)"/.exec(styleRaw) || [, "Block"])[1]
            readonly property string blinking: (/blinking\s*=\s*"(\w+)"/.exec(styleRaw) || [, "Off"])[1]

            Row {
                id: shapes
                spacing: 4
                Repeater {
                    model: ["Block", "Beam", "Underline"]
                    FlyoutChip {
                        required property var modelData
                        text: modelData
                        selected: shapes.parent.shape === modelData
                        onClicked: if (!selected) page.setCursor(modelData, shapes.parent.blinking)
                    }
                }
            }
            FlyoutChip {
                text: "Blink"
                selected: parent.blinking === "On" || parent.blinking === "Always"
                onClicked: page.setCursor(parent.shape, selected ? "Off" : "On")
            }
        }
    }

    function setCursor(shape, blinking) {
        // written as a plain string value so setToml's line replace fits it
        alacrittyFile.reload()
        alacrittyFile.waitForJob()
        var lines = alacrittyFile.text().split("\n")
        var cur = ""
        for (var i = 0; i < lines.length; i++) {
            var m = /^\s*\[([^\]]+)\]/.exec(lines[i])
            if (m) { cur = m[1].trim(); continue }
            if (cur === "cursor" && /^\s*style\s*=/.test(lines[i])) {
                lines[i] = 'style = { shape = "' + shape + '", blinking = "' + blinking + '" }'
                writeFile(alacrittyPath, lines.join("\n"), "Cursor: " + shape + (blinking === "Off" ? "" : ", blinking"), false)
                return
            }
        }
        // no style line: add one through the generic path
        var at = lines.findIndex(l => /^\s*\[cursor\]/.test(l))
        if (at < 0) lines.push("", "[cursor]", 'style = { shape = "' + shape + '", blinking = "' + blinking + '" }')
        else lines.splice(at + 1, 0, 'style = { shape = "' + shape + '", blinking = "' + blinking + '" }')
        writeFile(alacrittyPath, lines.join("\n"), "Cursor: " + shape, false)
    }

    Item { width: 1; height: 6 }
    FlyoutHeading { text: "BASH ALIASES · NEW TERMINALS ONLY" }

    Text {
        width: parent.width
        wrapMode: Text.WordWrap
        text: "Terminals already open keep their aliases until you run source ~/.bashrc in them."
        color: Theme.subtext
        font.family: Theme.fontText
        font.pixelSize: Theme.fontSmall
    }

    Repeater {
        model: page.aliases

        Item {
            id: aliasRow
            required property var modelData
            width: parent.width
            height: Theme.fs(26)

            Rectangle {
                anchors.fill: parent
                anchors.leftMargin: -4
                anchors.rightMargin: -4
                radius: Theme.radiusInner
                color: aliasMouse.containsMouse ? Theme.overlay : "transparent"
            }

            MouseArea {
                id: aliasMouse
                anchors.fill: parent
                hoverEnabled: true
                // click loads it into the fields below for editing
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    aliasName.text = aliasRow.modelData.name
                    aliasValue.text = aliasRow.modelData.value
                    aliasValue.forceFocus()
                }
            }

            Text {
                id: aliasNameText
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 120
                elide: Text.ElideRight
                text: aliasRow.modelData.name
                color: Theme.bright
                font.family: Theme.fontText
                font.pixelSize: Theme.fontBody
            }
            Text {
                anchors.left: aliasNameText.right
                anchors.leftMargin: 12
                anchors.right: removeChip.left
                anchors.rightMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: aliasRow.modelData.value
                color: Theme.text
                font.family: Theme.fontText
                font.pixelSize: Theme.fontBody
            }
            FlyoutChip {
                id: removeChip
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "Remove"
                enabled: !writeProc.running
                onClicked: page.removeAlias(aliasRow.modelData)
            }
        }
    }

    Item {
        width: parent.width
        height: Theme.fs(26)

        FlyoutInput {
            id: aliasName
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 112
            echoPassword: false
            placeholder: "name"
            onAccepted: aliasValue.forceFocus()
        }
        FlyoutInput {
            id: aliasValue
            anchors.left: aliasName.right
            anchors.leftMargin: 16
            anchors.right: saveChip.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            echoPassword: false
            placeholder: "command, e.g. git status"
            onAccepted: saveChip.clicked()
        }
        FlyoutChip {
            id: saveChip
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: page.aliases.some(a => a.name === aliasName.text.trim()) ? "Save" : "+ Add"
            enabled: !writeProc.running && aliasName.text.trim() !== ""
            onClicked: if (page.addAlias(aliasName.text, aliasValue.text)) {
                aliasName.text = ""
                aliasValue.text = ""
            }
        }
    }
}
