// Neutrino - Quickshell
// ~/.config/quickshell/HyprLuaWrite.qml
//
// The one write path into hyprland.lua, shared by the Keybinds editor and the
// Settings window's Input and Display pages.
//
// A write never goes straight at the config. The new text is syntax-checked
// with luac first, the current file is copied to a backup, and only then
// replaced -- followed by `hyprctl reload config-only` and a read of
// `hyprctl configerrors`, so a value Hyprland rejects is reported rather than
// silently doing nothing. Undo puts the backup back.
//
// Two ways in. write() takes a whole new file and leaves the staleness
// check to the caller (Keybinds, whose edits are offsets into the text it
// parsed). patch() takes a function of the current text instead -- for the
// Settings pages, which set one field by name and so can always be applied
// to whatever is on disk now. Patches made while a write is running queue
// up and apply in order.

import Quickshell
import Quickshell.Io
import QtQuick

Item {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string confPath: home + "/.config/hypr/hyprland.lua"
    readonly property string backupPath:
        (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/neutrino/hyprland.lua.bak"

    readonly property bool busy: proc.running

    // status: "ok" | "syntax" | "write". detail: luac's complaint for
    // syntax, the first error for write, `hyprctl configerrors` for ok.
    signal finished(string status, string detail)
    // patch()'s outcome, as one line for a status bar
    signal patched(bool ok, string message)

    property var queue: []

    FileView {
        id: confFile
        path: root.confPath
        blockLoading: true
        printErrors: false
    }

    // transform(text) returns the new text, or null when it can't make the
    // change (the field isn't a plain value); refusal is the message given
    function patch(transform, message, refusal) {
        queue = queue.concat([{ transform: transform, message: message, refusal: refusal }])
        if (!proc.running) next()
    }

    // Runs from both ends of a write -- the output collected and the process
    // reaped arrive in either order -- and goes ahead once both have.
    function next() {
        if (proc.running || current !== null) return
        while (queue.length > 0) {
            var job = queue[0]
            queue = queue.slice(1)
            confFile.reload()
            confFile.waitForJob()
            var src = confFile.text()
            if (src === "") { patched(false, "Couldn't read " + confPath); continue }
            var out = job.transform(src)
            if (out === null) { patched(false, job.refusal || "Not a plain value in hyprland.lua, edit it by hand"); continue }
            if (out === src) continue
            current = job
            write(out)
            return
        }
    }

    property var current: null

    onFinished: (status, detail) => {
        var job = current
        current = null
        if (job) {
            if (status === "syntax") patched(false, syntaxMessage(detail))
            else if (status !== "ok") patched(false, "Couldn't write hyprland.lua" + (detail ? ": " + detail.split("\n")[0] : ""))
            else if (reloadComplaint(detail) !== "") patched(false, "Written, but Hyprland reports: " + reloadComplaint(detail))
            else patched(true, job.message)
        }
        next()
    }

    function write(newText) {
        if (proc.running) return false
        proc.command = ["sh", "-c", writeScript, "sh", confPath, backupPath, newText]
        proc.running = true
        return true
    }

    function undo() {
        if (proc.running) return false
        proc.command = ["sh", "-c", undoScript, "sh", confPath, backupPath]
        proc.running = true
        return true
    }

    // "Written, but Hyprland reports: ..." or "" when the reload was clean
    function reloadComplaint(detail) {
        return detail !== "" && !/no errors/i.test(detail) ? detail.split("\n")[0] : ""
    }

    // luac names the temp file; only the line and message matter
    function syntaxMessage(detail) {
        var m = detail.match(/:(\d+):\s*(.*)/)
        return "Not written, Lua syntax error" + (m ? " on line " + m[1] + ": " + m[2] : "")
    }

    // Output's first line is a status word -- ok, syntax or write -- and the
    // rest is detail. Everything goes to stdout so one collector sees it all
    // in order.
    readonly property string writeScript: `
        exec 2>&1
        mkdir -p "\${2%/*}" && printf %s "$3" > "$2.new" || { echo write; exit; }
        if command -v luac >/dev/null 2>&1; then
            out=$(luac -p "$2.new" 2>&1) || { echo syntax; printf "%s\\n" "$out"; rm -f -- "$2.new"; exit; }
        fi
        cp -- "$1" "$2" && cat -- "$2.new" > "$1" || { echo write; exit; }
        rm -f -- "$2.new"
        hyprctl reload config-only >/dev/null
        sleep 0.3
        echo ok
        hyprctl configerrors`

    readonly property string undoScript: `
        exec 2>&1
        cat -- "$2" > "$1" || { echo write; exit; }
        hyprctl reload config-only >/dev/null
        sleep 0.3
        echo ok
        hyprctl configerrors`

    Process {
        id: proc
        command: ["true"]
        onRunningChanged: if (!running) root.next()
        stdout: StdioCollector {
            onStreamFinished: {
                var lines = text.split("\n")
                var status = lines.shift().trim()
                root.finished(status, lines.join("\n").trim())
            }
        }
    }
}
