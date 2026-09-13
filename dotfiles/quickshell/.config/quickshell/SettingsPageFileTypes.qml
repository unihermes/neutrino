// Neutrino - Quickshell
// ~/.config/quickshell/SettingsPageFileTypes.qml
//
// Which app opens what. The common kinds of file are grouped (a browser is
// http, https and html at once; images are a handful of types), and every
// other type an installed app declares is searchable below them.
//
// Candidates come from the MimeType= lines of the installed .desktop files --
// Quickshell's DesktopEntries doesn't expose them, so they're read directly.
// The current default is the first entry mimeapps.list gives, falling back
// to mimeinfo.cache's pick, the same order xdg-open resolves in.
//
// Writes go through `xdg-mime default`, which edits ~/.config/mimeapps.list.
// A group is only pointed at the types its chosen app actually declares, so
// picking an image viewer without SVG support leaves SVGs where they were.

import Quickshell.Io
import QtQuick

SettingsPage {
    id: page

    title: "File Types"
    description: "The app xdg-open and file managers launch for each kind of file. Saved to ~/.config/mimeapps.list."

    readonly property var groups: [
        { label: "Web browser",  types: ["x-scheme-handler/http", "x-scheme-handler/https", "text/html", "application/xhtml+xml"] },
        { label: "File manager", types: ["inode/directory"] },
        { label: "Text",         types: ["text/plain", "text/markdown", "application/json", "text/x-shellscript"] },
        { label: "PDF",          types: ["application/pdf"] },
        { label: "Images",       types: ["image/png", "image/jpeg", "image/gif", "image/webp", "image/svg+xml", "image/bmp"] },
        { label: "Video",        types: ["video/mp4", "video/x-matroska", "video/webm", "video/quicktime"] },
        { label: "Audio",        types: ["audio/mpeg", "audio/flac", "audio/ogg", "audio/x-wav"] },
        { label: "Archives",     types: ["application/zip", "application/x-tar", "application/gzip", "application/x-7z-compressed"] },
        { label: "Email links",  types: ["x-scheme-handler/mailto"] },
    ]

    // desktop id -> { id, name, types: [mime] }, apps declaring any type
    property var apps: ({})
    // desktop id -> Name, every entry -- a default can point at one that
    // declares no types (a browser's "userapp-" entry)
    property var names: ({})
    // mime -> desktop id, mimeapps.list's explicit choice
    property var defaults: ({})
    // mime -> desktop id, mimeinfo.cache's fallback
    property var cached: ({})
    property bool loaded: false
    property string query: ""

    function appName(id) {
        return names[id] || id.replace(/\.desktop$/, "")
    }

    function current(mime) {
        var d = defaults[mime]
        return d !== undefined ? d : (cached[mime] || "")
    }

    // apps declaring any of these types, by name
    function candidates(types) {
        var out = []
        for (var id in apps) {
            var a = apps[id]
            if (types.some(t => a.types.indexOf(t) >= 0)) out.push(a)
        }
        return out.sort((x, y) => x.name.localeCompare(y.name))
    }

    // The group's default, if its types agree; "mixed" if they don't.
    function groupCurrent(types) {
        var seen = ""
        for (var i = 0; i < types.length; i++) {
            var c = current(types[i])
            if (c === "") continue
            if (seen === "") seen = c
            else if (seen !== c) return "mixed"
        }
        return seen
    }

    function setDefault(appId, types) {
        var declared = apps[appId] ? types.filter(t => apps[appId].types.indexOf(t) >= 0) : types
        if (declared.length === 0) return
        setProc.pending = appName(appId) + " now opens " + (declared.length === 1 ? declared[0] : declared.length + " types")
        setProc.command = ["xdg-mime", "default", appId].concat(declared)
        setProc.running = true
    }

    // every type some app declares, filtered by the search
    readonly property var allTypes: {
        if (!loaded) return []
        var q = query.trim().toLowerCase()
        if (q === "") return []
        var set = {}
        for (var id in apps) apps[id].types.forEach(t => set[t] = true)
        return Object.keys(set)
            .filter(t => t.indexOf(q) >= 0 || candidates([t]).some(a => a.name.toLowerCase().indexOf(q) >= 0))
            .sort()
            .slice(0, 80)
    }

    Component.onCompleted: {
        scanProc.running = true
        defaultsProc.running = true
    }

    // One record per .desktop file, user copies shadowing system ones:
    // id <TAB> Name <TAB> MimeType. Only the [Desktop Entry] group counts --
    // Actions carry Name= lines too. Hidden=true entries are deletions.
    Process {
        id: scanProc
        command: ["sh", "-c", `
            IFS=:
            for d in "\${XDG_DATA_HOME:-$HOME/.local/share}" \${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
                [ -d "$d/applications" ] || continue
                find "$d/applications" -name '*.desktop' 2>/dev/null | while read -r f; do
                    id=\${f#"$d/applications/"}
                    awk -v id="$(printf %s "$id" | tr / -)" -F= '
                        /^\\[/ { inmain = ($0 == "[Desktop Entry]") }
                        inmain && $1 == "Name" && name == "" { name = substr($0, 6) }
                        inmain && $1 == "MimeType" { mime = substr($0, 10) }
                        inmain && $1 == "Hidden" && $2 == "true" { hidden = 1 }
                        END { printf "%s\\t%s\\t%s\\t%s\\n", id, name, mime, hidden }' "$f"
                done
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                var out = {}
                text.split("\n").forEach(line => {
                    var f = line.split("\t")
                    if (f.length < 4 || out[f[0]] !== undefined) return
                    // first one seen wins, hidden or not, so a user's
                    // Hidden=true copy removes the system entry
                    out[f[0]] = f[3] === "1" ? null
                        : { id: f[0], name: f[1] || f[0], types: f[2].split(";").filter(t => t !== "") }
                })
                var apps = {}, names = {}
                for (var id in out) {
                    if (!out[id]) continue
                    names[id] = out[id].name
                    if (out[id].types.length) apps[id] = out[id]
                }
                page.apps = apps
                page.names = names
                page.loaded = true
            }
        }
    }

    // mimeapps.list's [Default Applications] in precedence order, then
    // mimeinfo.cache. D <TAB> mime <TAB> first-app, C likewise.
    Process {
        id: defaultsProc
        command: ["sh", "-c", `
            IFS=:
            cfg=\${XDG_CONFIG_HOME:-$HOME/.config}
            data=\${XDG_DATA_HOME:-$HOME/.local/share}
            for f in "$cfg/mimeapps.list" $(printf %s "\${XDG_CONFIG_DIRS:-/etc/xdg}" | sed 's|:|/mimeapps.list:|g; s|$|/mimeapps.list|') \
                     "$data/applications/mimeapps.list" $(printf %s "\${XDG_DATA_DIRS:-/usr/local/share:/usr/share}" | sed 's|:|/applications/mimeapps.list:|g; s|$|/applications/mimeapps.list|'); do
                [ -f "$f" ] && awk -F= '/^\\[/ { on = ($0 == "[Default Applications]") } on && NF > 1 { split($2, a, ";"); if (a[1] != "") printf "D\\t%s\\t%s\\n", $1, a[1] }' "$f"
            done
            for d in "$data" \${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
                f="$d/applications/mimeinfo.cache"
                [ -f "$f" ] && awk -F= '/^\\[/ { on = ($0 == "[MIME Cache]") } on && NF > 1 { split($2, a, ";"); if (a[1] != "") printf "C\\t%s\\t%s\\n", $1, a[1] }' "$f"
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                var d = {}, c = {}
                text.split("\n").forEach(line => {
                    var f = line.split("\t")
                    if (f.length < 3) return
                    var map = f[0] === "D" ? d : c
                    if (map[f[1]] === undefined) map[f[1]] = f[2]
                })
                page.defaults = d
                page.cached = c
            }
        }
    }

    Process {
        id: setProc
        property string pending: ""
        stderr: StdioCollector { id: setErr }
        onExited: code => {
            if (code === 0) page.say(pending, false)
            else page.say("xdg-mime failed: " + (setErr.text.trim().split("\n")[0] || "exit " + code), true)
            defaultsProc.running = true
        }
    }

    // --- layout --------------------------------------------------------------

    component HandlerRow: SettingsField {
        id: hr
        property var types: []
        readonly property var apps: page.candidates(types)
        readonly property string chosen: page.groupCurrent(types)

        labelWidth: 200
        hint: chosen === "mixed" ? "Mixed -- pick one to set them all"
            : chosen === "" ? "Nothing set"
            : page.names[chosen] ? page.appName(chosen)
            : chosen + " (not installed)"

        Flow {
            anchors.right: parent.right
            width: parent.width
            spacing: 4

            Repeater {
                model: hr.apps
                FlyoutChip {
                    required property var modelData
                    text: modelData.name
                    selected: hr.chosen === modelData.id
                    enabled: !setProc.running
                    onClicked: page.setDefault(modelData.id, hr.types)
                }
            }

            Text {
                visible: hr.apps.length === 0
                height: Theme.fs(20)
                verticalAlignment: Text.AlignVCenter
                text: page.loaded ? "No installed app declares this" : "Reading apps…"
                color: Theme.muted
                font.family: Theme.fontText
                font.pixelSize: Theme.fontSmall
            }
        }
    }

    Repeater {
        model: page.groups
        HandlerRow {
            required property var modelData
            label: modelData.label
            types: modelData.types
        }
    }

    Item { width: 1; height: 6 }
    FlyoutHeading { text: "EVERY TYPE" }

    FlyoutInput {
        id: search
        placeholder: "Search a type or an app: image/avif, zathura, x-scheme-handler"
        echoPassword: false
        onTextChanged: page.query = text
        onEscapePressed: if (text !== "") text = ""
    }

    Repeater {
        model: page.allTypes
        HandlerRow {
            required property var modelData
            label: modelData
            types: [modelData]
        }
    }

    Text {
        visible: page.query.trim() !== "" && page.allTypes.length === 0
        width: parent.width
        horizontalAlignment: Text.AlignHCenter
        topPadding: 8
        text: "No installed app declares a type matching \"" + page.query.trim() + "\""
        color: Theme.subtext
        font.family: Theme.fontText
        font.pixelSize: Theme.fontBody
    }
}
