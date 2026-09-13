// Neutrino - Quickshell
// ~/.config/quickshell/System.qml
//
// System: live usage gauges with per-core bars and 60-second history,
// network throughput, the heaviest processes, static facts, hardware specs
// and config shortcuts, in one standalone window opened from the Control
// Centre. Appearance settings are deliberately not duplicated here -- they
// live on the Appearance page.
//
// Nearly everything live is read straight from procfs/sysfs with FileView
// rather than by running tools: /proc/stat for CPU and each core,
// /proc/meminfo for RAM and swap, the coretemp hwmon node for temperature
// (the same file `sensors` reads), and the interface byte counters for
// network speed. Re-reading a file each second costs next to nothing;
// spawning `sensors` or `free` each second would mean several processes a
// second for as long as the window is up.
//
// What does shell out, none of it per-second: `top` for the process list
// (every 3s), `df` for the root filesystem (every 30s), `pacman -Q` for the
// package counts, `lspci`/`lsblk`/DMI for the specs section, and a one-off
// search for the temperature sensor's hwmon node -- all once per open, since
// none of it changes while the window is up.
//
// Nothing polls while the window is closed.

import Quickshell
import Quickshell.Io
import QtQuick

CentredWindow {
    id: root

    heading: "SYSTEM"
    contentWidth: 2 * colWidth + colGap

    readonly property int colWidth: 370
    readonly property int colGap: 28
    // samples of history kept for the graphs, one per second
    readonly property int historyLength: 60

    // --- state ---------------------------------------------------------

    property real cpu: 0          // 0..1
    property var cores: []        // 0..1 per core
    property real mem: 0          // 0..1
    property real memUsedKb: 0
    property real memTotalKb: 0
    property real swap: 0         // 0..1
    property real swapTotalKb: 0
    property real diskUsed: 0     // bytes
    property real diskSize: 0
    property real tempC: -1       // -1 = no sensor found
    property string iface: ""
    property real rxRate: -1      // bytes/s, -1 until two samples exist
    property real txRate: -1
    property real uptimeSec: 0
    property string kernel: ""
    property string hostname: ""
    property int pkgCount: -1
    property int aurCount: -1

    // --- specs (static; gathered once per open, not polled) -------------

    property string cpuModel: ""
    property string gpuModel: ""
    property string gpuDriver: ""
    property string mesaVersion: ""
    property string board: ""
    // [{ name, size, model }], real disks only -- lsblk lists the two
    // read-only "loop-like" card-reader placeholders on this laptop as 0B
    // disks, which is noise rather than storage
    property var storage: []
    // [{ name, width, height, hz }]
    property var monitors: []

    // Histories are replaced, never mutated in place: a push onto the same
    // array doesn't notify, and the graphs would never repaint.
    property var cpuHistory: []
    property var rxHistory: []
    property var txHistory: []

    // [{ pid, user, cpu, memKb, name }], heaviest first
    property var procs: []
    property string procSort: "cpu"      // "cpu" | "mem"
    readonly property string me: Quickshell.env("USER")

    // previous samples, for the deltas
    property var cpuPrev: null
    property var corePrev: []
    property var netPrev: null

    function pushHistory(arr, v) {
        return arr.concat([v]).slice(-historyLength)
    }

    // --- formatting ----------------------------------------------------

    function pct(f) { return Math.round(f * 100) + "%" }

    // binary units, labelled the way df -h and free -h label them
    function gib(bytes) {
        var g = bytes / 1073741824
        return g >= 100 ? g.toFixed(0) + "G" : g.toFixed(1) + "G"
    }

    function kib(kb) {
        if (kb >= 1048576) return (kb / 1048576).toFixed(1) + "G"
        return Math.round(kb / 1024) + "M"
    }

    function rate(bps) {
        if (bps < 0) return "--"
        if (bps >= 1048576) return (bps / 1048576).toFixed(1) + " MB/s"
        if (bps >= 1024) return Math.round(bps / 1024) + " KB/s"
        return Math.round(bps) + " B/s"
    }

    function duration(s) {
        var d = Math.floor(s / 86400)
        var h = Math.floor((s % 86400) / 3600)
        var m = Math.floor((s % 3600) / 60)
        if (d > 0) return d + "d " + h + "h"
        if (h > 0) return h + "h " + m + "m"
        return m + "m"
    }

    // --- sampling ------------------------------------------------------

    FileView { id: statFile;    path: "/proc/stat";    blockLoading: true }
    FileView { id: memFile;     path: "/proc/meminfo"; blockLoading: true }
    FileView { id: uptimeFile;  path: "/proc/uptime";  blockLoading: true }
    FileView { id: routeFile;   path: "/proc/net/route"; blockLoading: true }
    FileView { id: kernelFile;  path: "/proc/sys/kernel/osrelease"; blockLoading: true }
    FileView { id: hostFile;    path: "/proc/sys/kernel/hostname";  blockLoading: true }
    FileView {
        id: tempFile
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: rxFile
        path: root.iface !== "" ? "/sys/class/net/" + root.iface + "/statistics/rx_bytes" : ""
        blockLoading: true
        printErrors: false
    }
    FileView {
        id: txFile
        path: root.iface !== "" ? "/sys/class/net/" + root.iface + "/statistics/tx_bytes" : ""
        blockLoading: true
        printErrors: false
    }

    // "cpu  user nice system idle iowait irq softirq steal ..." -> busy
    // fraction since the previous sample, or -1 with no previous sample
    function busy(fields, prev) {
        var f = fields.slice(1, 9).map(Number)
        var idle = f[3] + f[4]
        var total = f.reduce((a, b) => a + b, 0)
        var frac = -1
        if (prev) {
            var dt = total - prev.total
            if (dt > 0) frac = Math.max(0, Math.min(1, 1 - (idle - prev.idle) / dt))
        }
        return { frac: frac, sample: { idle: idle, total: total } }
    }

    function sampleCpu() {
        statFile.reload()
        var lines = statFile.text().split("\n")
        var nextCores = [], nextPrev = []
        for (var i = 0; i < lines.length; i++) {
            var f = lines[i].trim().split(/\s+/)
            if (f[0] === "cpu") {
                var all = busy(f, cpuPrev)
                if (all.frac >= 0) {
                    cpu = all.frac
                    cpuHistory = pushHistory(cpuHistory, all.frac)
                }
                cpuPrev = all.sample
            } else if (/^cpu\d+$/.test(f[0])) {
                var n = nextPrev.length
                var c = busy(f, corePrev[n])
                nextCores.push(Math.max(0, c.frac))
                nextPrev.push(c.sample)
            } else if (f[0] !== "" && !f[0].startsWith("cpu")) {
                break   // the cpu lines come first; nothing after is needed
            }
        }
        if (corePrev.length === nextPrev.length) cores = nextCores
        corePrev = nextPrev
    }

    function sampleMem() {
        memFile.reload()
        var kv = {}
        var lines = memFile.text().split("\n")
        for (var i = 0; i < lines.length; i++) {
            var m = lines[i].match(/^(\w+):\s+(\d+)/)
            if (m) kv[m[1]] = Number(m[2])
        }
        memTotalKb = kv.MemTotal || 0
        // MemAvailable, not MemFree: free memory excludes the page cache the
        // kernel will hand back the moment anything asks, so "used" computed
        // from it reads 80% on a machine that is mostly idle
        memUsedKb = memTotalKb - (kv.MemAvailable || 0)
        mem = memTotalKb > 0 ? memUsedKb / memTotalKb : 0
        swapTotalKb = kv.SwapTotal || 0
        swap = swapTotalKb > 0 ? (swapTotalKb - (kv.SwapFree || 0)) / swapTotalKb : 0
    }

    function sampleTemp() {
        if (tempFile.path === "") return
        tempFile.reload()
        var t = tempFile.text().trim()
        var v = Number(t)
        tempC = (t === "" || isNaN(v)) ? -1 : v / 1000
    }

    function sampleNet() {
        // The default route's interface, re-read each sample so switching
        // from wifi to ethernet (or a VPN) follows without reopening.
        routeFile.reload()
        var best = "", bestMetric = Infinity
        var lines = routeFile.text().split("\n")
        for (var i = 1; i < lines.length; i++) {
            var f = lines[i].trim().split(/\s+/)
            if (f.length < 7 || f[1] !== "00000000") continue
            if (Number(f[6]) < bestMetric) { best = f[0]; bestMetric = Number(f[6]) }
        }
        if (best !== iface) {
            // new counters, so the old baseline would produce a garbage delta
            iface = best
            netPrev = null
            rxRate = txRate = -1
        }
        if (iface === "") return

        rxFile.reload(); txFile.reload()
        var now = Date.now()
        var rx = Number(rxFile.text().trim()), tx = Number(txFile.text().trim())
        if (isNaN(rx) || isNaN(tx)) return
        if (netPrev) {
            var dt = (now - netPrev.t) / 1000
            if (dt > 0) {
                rxRate = Math.max(0, (rx - netPrev.rx) / dt)
                txRate = Math.max(0, (tx - netPrev.tx) / dt)
                rxHistory = pushHistory(rxHistory, rxRate)
                txHistory = pushHistory(txHistory, txRate)
            }
        }
        netPrev = { t: now, rx: rx, tx: tx }
    }

    function sampleUptime() {
        uptimeFile.reload()
        uptimeSec = Number(uptimeFile.text().split(" ")[0]) || 0
    }

    function sampleAll() {
        sampleCpu(); sampleMem(); sampleTemp(); sampleNet(); sampleUptime()
    }

    // 1s: a gauge that lags two seconds behind a spike reads as broken
    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.sampleAll()
    }

    Timer {
        interval: 30000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: diskProc.running = true
    }

    Timer {
        interval: 3000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root.refreshProcs()
    }

    // the sort a run was started with; see onStreamFinished
    property string procRunSort: ""

    function refreshProcs() {
        if (procProc.running) return
        procRunSort = procSort
        procProc.running = true
    }

    onVisibleChanged: if (visible) {
        // Stale baselines from the last time the window was open would turn
        // the first reading into an average over however long it was shut,
        // and old history would draw a graph with a gap-less lie in it.
        cpuPrev = null
        corePrev = []
        cores = []
        netPrev = null
        rxRate = txRate = -1
        cpuHistory = []
        rxHistory = []
        txHistory = []
        procs = []
        killPid = -1
        kernelFile.reload()
        hostFile.reload()
        kernel = kernelFile.text().trim()
        hostname = hostFile.text().trim()
        pkgProc.running = true
        if (tempFile.path === "") tempProbe.running = true
        // static for the life of the machine's session; no need to re-probe
        // on every reopen the way the live gauges reset above
        if (cpuModel === "") specsProc.running = true
        if (monitors.length === 0) monitorsProc.running = true
    }

    // One shell script, one round trip: CPU model from /proc/cpuinfo, the
    // first VGA/3D controller lspci reports plus the kernel driver it's
    // bound to, mesa's package version, DMI board vendor + product name, and
    // the disk block devices with a real size. `column -t` isn't used --
    // fixed-width awk fields would fall over on a model name with spaces, so
    // each record is pipe-separated instead and split in onStreamFinished.
    Process {
        id: specsProc
        command: ["sh", "-c",
            "awk -F: '/model name/{print $2; exit}' /proc/cpuinfo\n"
            + "echo ---\n"
            + "lspci -k | awk '/VGA compatible|3D controller/{sub(/^[0-9a-f:.]+ /,\"\"); "
            + "sub(/^(VGA compatible controller|3D controller): /,\"\"); print; getline; "
            + "if ($0 ~ /Kernel driver in use/) { sub(/.*: /,\"\"); print } else print \"\"; exit}'\n"
            + "echo ---\n"
            + "pacman -Q mesa 2>/dev/null | awk '{print $2}'\n"
            + "echo ---\n"
            + "cat /sys/class/dmi/id/sys_vendor 2>/dev/null\n"
            + "cat /sys/class/dmi/id/product_name 2>/dev/null\n"
            + "echo ---\n"
            + "lsblk -d -n -o NAME,SIZE,MODEL,TYPE,TRAN"]
        stdout: StdioCollector {
            onStreamFinished: {
                var parts = text.split("\n---\n")
                root.cpuModel = (parts[0] || "").trim()
                var gpu = (parts[1] || "").trim().split("\n")
                root.gpuModel = (gpu[0] || "").trim()
                root.gpuDriver = (gpu[1] || "").trim()
                root.mesaVersion = (parts[2] || "").trim()
                var dmi = (parts[3] || "").trim().split("\n")
                root.board = [dmi[0], dmi[1]].filter(s => s && s.trim() !== "").join(" ").trim()
                var disks = []
                var lines = (parts[4] || "").trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    if (lines[i].trim() === "") continue
                    // NAME and SIZE never contain spaces, so they're safe to
                    // shift off the front; MODEL is whatever's left in the
                    // middle once TRAN and TYPE (the two before it) are
                    // peeled off the end -- MODEL is the one field that can
                    // itself contain spaces ("Micron 1024GB NVMe")
                    var f = lines[i].trim().split(/\s+/)
                    if (f.length < 4) continue
                    var tran = f.pop(), type = f.pop(), name = f.shift(), size = f.shift()
                    // real disks with a real bus only: card-reader slots
                    // report a 0B "disk" with no media in them, and zram is
                    // compressed RAM masquerading as a block device (tran "")
                    if (type !== "disk" || size === "0B" || tran === "") continue
                    disks.push({ name: name, size: size, model: f.join(" ") || "--", tran: tran })
                }
                root.storage = disks
            }
        }
    }

    // Refresh rate isn't in Quickshell's own Screen type, only in Hyprland's
    // IPC -- and unlike Quickshell.screens, that's already keyed by name in
    // an order matching nothing in particular, so match by name below rather
    // than assuming the two lists line up.
    Process {
        id: monitorsProc
        command: ["hyprctl", "monitors", "-j"]
        stdout: StdioCollector {
            onStreamFinished: {
                var data
                try { data = JSON.parse(text) } catch (e) { return }
                root.monitors = data.map(m => ({
                    name: m.name, width: m.width, height: m.height,
                    hz: Math.round(m.refreshRate),
                }))
            }
        }
    }

    Process {
        id: diskProc
        command: ["df", "-B1", "--output=size,used", "/"]
        stdout: StdioCollector {
            onStreamFinished: {
                var f = text.trim().split("\n").pop().trim().split(/\s+/)
                if (f.length >= 2) {
                    root.diskSize = Number(f[0])
                    root.diskUsed = Number(f[1])
                }
            }
        }
    }

    // pacman -Qm is exactly the AUR set: packages installed from outside the
    // sync repos. That's what yay counts too, without needing yay.
    Process {
        id: pkgProc
        command: ["sh", "-c", "pacman -Qq | wc -l; pacman -Qqm | wc -l"]
        stdout: StdioCollector {
            onStreamFinished: {
                var f = text.trim().split("\n")
                root.pkgCount = Number(f[0])
                root.aurCount = Number(f[1])
            }
        }
    }

    // First CPU package sensor by driver: Intel, then AMD's two drivers,
    // then ARM SoCs, then the ACPI zone as a last resort.
    Process {
        id: tempProbe
        command: ["sh", "-c",
            "for want in coretemp k10temp zenpower cpu_thermal acpitz; do "
            + "for d in /sys/class/hwmon/hwmon*; do "
            + "[ \"$(cat $d/name 2>/dev/null)\" = \"$want\" ] && [ -r $d/temp1_input ] "
            + "&& { echo $d/temp1_input; exit 0; }; done; done"]
        stdout: StdioCollector {
            onStreamFinished: {
                var p = text.trim()
                if (p !== "") { tempFile.path = p; root.sampleTemp() }
            }
        }
    }

    // Heaviest processes. top, not ps: ps's %CPU is each process's average
    // over its whole lifetime, so a browser that spiked an hour ago outranks
    // whatever is pinning a core right now. top's *second* frame (-n 2) is a
    // real 1-second sample -- its first frame has the same lifetime-average
    // problem. -e k keeps RES in plain KiB instead of "1.2g".
    Process {
        id: procProc
        command: ["sh", "-c",
            "top -b -n 2 -d 1 -o " + (root.procSort === "mem" ? "%MEM" : "%CPU")
            + " -e k -w 512 | awk '/^top -/{f++} f==2 && /^ *[0-9]+ /{"
            + "c=$12; for(i=13;i<=NF;i++) c=c\" \"$i; if (c==\"top\") next; "
            + "print $1\"|\"$2\"|\"$9\"|\"$6\"|\"c; if(++n==5) exit}'"]
        stdout: StdioCollector {
            onStreamFinished: {
                // held while the pointer is over the list, so a row can't
                // reshuffle out from under a click on its kill button
                if (procList.hovered) return
                // A run takes a second, so one started just before the sort
                // was switched can land after it and paint the old order
                // over the new heading. Drop it; the next run is the right one.
                if (root.procRunSort !== root.procSort) { root.refreshProcs(); return }
                var out = []
                var lines = text.trim().split("\n")
                for (var i = 0; i < lines.length; i++) {
                    var f = lines[i].split("|")
                    if (f.length < 5) continue
                    out.push({ pid: Number(f[0]), user: f[1], cpu: Number(f[2]),
                               memKb: Number(f[3]), name: f[4] })
                }
                // top already sorted, but by its own rounding of the column;
                // this keeps ties and near-ties in a stable, visible order
                var key = root.procSort === "mem" ? "memKb" : "cpu"
                out.sort((a, b) => b[key] - a[key])
                root.procs = out
            }
        }
    }

    onProcSortChanged: if (visible) {
        procs = []
        refreshProcs()
    }

    // Two-step kill. The first click arms the button for that *pid* (not
    // that row), the second sends SIGTERM. Arming expires after 3s, and the
    // list freezes while hovered, so a refresh can't move a different
    // process under the confirming click.
    property int killPid: -1

    Timer {
        id: killDisarm
        interval: 3000
        onTriggered: root.killPid = -1
    }

    function requestKill(pid) {
        if (killPid !== pid) {
            killPid = pid
            killDisarm.restart()
            return
        }
        killPid = -1
        killDisarm.stop()
        killProc.command = ["kill", String(pid)]
        killProc.running = true
    }

    Process {
        id: killProc
        command: ["true"]
        onExited: root.refreshProcs()
    }

    // --- copy / quick links ----------------------------------------------

    property bool copied: false

    function copySummary() {
        var lines = [
            "Host: " + hostname, "Kernel: " + kernel, "Uptime: " + duration(uptimeSec),
            "CPU: " + (cpuModel || "--"),
            "GPU: " + (gpuModel || "--") + (gpuDriver ? " (" + gpuDriver + ")" : ""),
            "Mesa: " + (mesaVersion || "--"),
            "RAM: " + kib(memTotalKb),
            "Board: " + (board || "--"),
            "Storage: " + (storage.length ? storage.map(d => d.model + " " + d.size).join(", ") : "--"),
            "Monitors: " + (monitors.length
                ? monitors.map(m => m.name + " " + m.width + "x" + m.height + "@" + m.hz + "Hz").join(", ") : "--"),
            "Packages: " + (pkgCount < 0 ? "--" : pkgCount + " (" + aurCount + " AUR)"),
        ]
        // the text goes in argv, not down stdin -- Process exposes no way to
        // close stdin's write end, and wl-copy blocks reading until EOF
        copyProc.command = ["sh", "-c", "printf %s \"$1\" | wl-copy", "sh", lines.join("\n") + "\n"]
        copyProc.running = true
        copied = true
        copiedTimer.restart()
    }

    Timer { id: copiedTimer; interval: 1600; onTriggered: root.copied = false }

    Process { id: copyProc; command: ["true"] }

    // --- pieces ----------------------------------------------------------

    // label | bar | value, on one line
    component Gauge: Item {
        id: g
        property string label: ""
        property real fraction: 0
        property string value: ""
        // lights the fill with the one alert hue in the palette
        property bool critical: false
        property bool available: true

        width: parent ? parent.width : 0
        height: 22

        Text {
            id: gLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 48
            text: g.label
            color: Theme.text
            font.family: Theme.fontText
            font.pixelSize: Theme.fontBody
        }

        Rectangle {
            anchors.left: gLabel.right
            anchors.right: gValue.left
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            height: 8
            radius: height / 2
            color: Theme.base
            border.width: 1
            border.color: Theme.surface

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                // clamped to its own diameter, so a near-zero reading is a
                // rounded stub rather than a sliver with clipped corners
                width: !g.available || g.fraction <= 0 ? 0
                    : Math.max(height, parent.width * Math.min(1, g.fraction))
                radius: parent.radius
                color: g.critical ? Theme.alert : Theme.text

                Behavior on width { NumberAnimation { duration: Theme.dur(250); easing.type: Easing.OutCubic } }
            }
        }

        Text {
            id: gValue
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            // wide enough for "210G / 476G" so every bar is the same length
            width: 90
            horizontalAlignment: Text.AlignRight
            text: g.value
            color: g.available ? Theme.bright : Theme.subtext
            font.family: Theme.fontText
            font.pixelSize: Theme.fontBody
        }
    }

    // label on the left, value on the right
    component Info: Item {
        id: info
        property string label: ""
        property string value: ""

        width: parent ? parent.width : 0
        height: 20

        Text {
            id: infoLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: info.label
            color: Theme.text
            font.family: Theme.fontText
            font.pixelSize: Theme.fontBody
        }

        Text {
            anchors.left: infoLabel.right
            anchors.leftMargin: 8
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: info.value
            color: Theme.bright
            font.family: Theme.fontText
            font.pixelSize: Theme.fontBody
        }
    }

    // A 60-second line graph. Newest sample at the right edge; while history
    // is still filling, the line starts partway across rather than stretching
    // a few seconds over the whole width.
    component Spark: Item {
        id: sp
        // [{ values, color, fill }] drawn in order, so put the one that
        // should sit on top last
        property var series: []
        property real ceiling: 1
        property string caption: ""

        width: parent ? parent.width : 0
        height: 44

        onSeriesChanged: canvas.requestPaint()
        onCeilingChanged: canvas.requestPaint()

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusInner
            color: Theme.base
            border.width: 1
            border.color: Theme.surface
        }

        Canvas {
            id: canvas
            anchors.fill: parent
            anchors.margins: 3
            onWidthChanged: requestPaint()

            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                var w = width, h = height
                var step = w / (root.historyLength - 1)
                for (var s = 0; s < sp.series.length; s++) {
                    var vals = sp.series[s].values
                    if (!vals || vals.length < 2) continue
                    var x0 = w - (vals.length - 1) * step
                    ctx.beginPath()
                    for (var i = 0; i < vals.length; i++) {
                        var y = h - Math.min(1, vals[i] / sp.ceiling) * h
                        if (i === 0) ctx.moveTo(x0, y)
                        else ctx.lineTo(x0 + i * step, y)
                    }
                    ctx.strokeStyle = sp.series[s].color
                    ctx.lineWidth = 1.5
                    ctx.lineJoin = "round"
                    ctx.stroke()
                    if (sp.series[s].fill) {
                        ctx.lineTo(w, h)
                        ctx.lineTo(x0, h)
                        ctx.closePath()
                        ctx.globalAlpha = 0.14
                        ctx.fillStyle = sp.series[s].color
                        ctx.fill()
                        ctx.globalAlpha = 1
                    }
                }
            }
        }

        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            text: sp.caption
            color: Theme.subtext
            font.family: Theme.fontText
            font.pixelSize: Theme.fontSmall
        }
    }

    component SortButton: Item {
        id: sb
        property string label: ""
        property string key: ""
        readonly property bool on: root.procSort === key

        width: sbText.implicitWidth + 12
        height: 18

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusInner
            color: sb.on ? Theme.overlay : (sbMouse.containsMouse ? Theme.surface : "transparent")
            border.width: 1
            border.color: sb.on ? Theme.muted : "transparent"
        }

        Text {
            id: sbText
            anchors.centerIn: parent
            text: sb.label
            color: sb.on ? Theme.bright : Theme.subtext
            font.family: Theme.fontText
            font.pixelSize: Theme.fontSmall
            font.bold: true
        }

        MouseArea {
            id: sbMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.procSort = sb.key
        }
    }

    // --- layout ----------------------------------------------------------

    Row {
        spacing: root.colGap

        // ---- left: usage + network ----
        Column {
            width: root.colWidth
            spacing: 6

            FlyoutHeading { text: "USAGE" }

            Gauge {
                label: "CPU"
                fraction: root.cpu
                value: root.cpuHistory.length > 0 ? root.pct(root.cpu) : "--"
            }

            // one bar per core, under the CPU gauge's bar
            Item {
                width: parent.width
                height: 26

                Row {
                    id: coreRow
                    x: 48
                    width: parent.width - 48 - 90 - 12
                    height: parent.height
                    spacing: 3
                    readonly property int n: Math.max(1, root.cores.length)

                    Repeater {
                        model: root.cores

                        Rectangle {
                            required property var modelData
                            width: (coreRow.width - (coreRow.n - 1) * coreRow.spacing) / coreRow.n
                            height: coreRow.height
                            radius: 2
                            color: Theme.base
                            border.width: 1
                            border.color: Theme.surface

                            Rectangle {
                                anchors.bottom: parent.bottom
                                anchors.left: parent.left
                                anchors.right: parent.right
                                height: Math.max(modelData > 0 ? 2 : 0, parent.height * modelData)
                                radius: 2
                                color: Theme.text

                                Behavior on height { NumberAnimation { duration: Theme.dur(250); easing.type: Easing.OutCubic } }
                            }
                        }
                    }
                }

                Text {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 90
                    horizontalAlignment: Text.AlignRight
                    // the busiest core, since an average hides a single
                    // pinned thread
                    text: root.cores.length > 0
                        ? "peak " + root.pct(Math.max.apply(null, root.cores)) : ""
                    color: Theme.subtext
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontSmall
                }
            }

            Spark {
                series: [{ values: root.cpuHistory, color: Theme.text, fill: true }]
                ceiling: 1
                caption: "CPU · 60s"
            }

            Gauge {
                label: "RAM"
                fraction: root.mem
                value: root.pct(root.mem)
                critical: root.mem >= 0.9
            }

            Gauge {
                label: "Swap"
                fraction: root.swap
                available: root.swapTotalKb > 0
                value: root.swapTotalKb > 0 ? root.pct(root.swap) : "none"
            }

            Gauge {
                label: "Disk"
                fraction: root.diskSize > 0 ? root.diskUsed / root.diskSize : 0
                value: root.diskSize > 0 ? root.gib(root.diskUsed) + " / " + root.gib(root.diskSize) : "--"
                critical: root.diskSize > 0 && root.diskUsed / root.diskSize >= 0.9
            }

            Gauge {
                label: "Temp"
                // 100C spans the bar: Intel mobile chips throttle in the high
                // 90s, so a full bar means what it looks like it means
                fraction: root.tempC / 100
                available: root.tempC >= 0
                value: root.tempC >= 0 ? Math.round(root.tempC) + "°C" : "no sensor"
                critical: root.tempC >= 90
            }

            Item { width: 1; height: 4 }
            FlyoutHeading { text: "NETWORK" }

            Info { label: "Interface"; value: root.iface !== "" ? root.iface : "offline" }
            Info { label: "Download";  value: "↓ " + root.rate(root.rxRate) }
            Info { label: "Upload";    value: "↑ " + root.rate(root.txRate) }

            Spark {
                // Download bright and filled, upload dimmer on top. The
                // ceiling tracks the busiest second in view but never drops
                // below 64 KB/s, or an idle link would blow background chatter
                // up to full height and look like a transfer.
                readonly property real peak: Math.max(65536,
                    Math.max.apply(null, root.rxHistory.concat(root.txHistory, [0])))
                series: [
                    { values: root.rxHistory, color: Theme.text, fill: true },
                    { values: root.txHistory, color: Theme.subtext, fill: false },
                ]
                ceiling: peak
                caption: "↓ ↑ · peak " + root.rate(peak)
            }

            Item { width: 1; height: 4 }
            Item {
                width: parent.width
                height: 18

                FlyoutHeading {
                    anchors.left: parent.left
                    anchors.right: sortRow.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "PROCESSES"
                }

                Row {
                    id: sortRow
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    SortButton { label: "CPU"; key: "cpu" }
                    SortButton { label: "MEM"; key: "mem" }
                }
            }

            // column headings
            Item {
                width: parent.width
                height: 16

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Name"
                    color: Theme.subtext
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontSmall
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 22 + 8 + 60 + 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    horizontalAlignment: Text.AlignRight
                    text: "CPU"
                    color: root.procSort === "cpu" ? Theme.text : Theme.subtext
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontSmall
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 22 + 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 60
                    horizontalAlignment: Text.AlignRight
                    text: "MEM"
                    color: root.procSort === "mem" ? Theme.text : Theme.subtext
                    font.family: Theme.fontText
                    font.pixelSize: Theme.fontSmall
                }
            }

            Column {
                id: procList
                width: parent.width
                spacing: 2
                // five rows' worth, so the column doesn't jump while a sort
                // change is loading
                height: 5 * 24 + 4 * spacing

                readonly property bool hovered: procHover.hovered
                HoverHandler { id: procHover }

                Repeater {
                    model: root.procs

                    Item {
                        id: pr
                        required property var modelData
                        readonly property bool mine: modelData.user === root.me
                        readonly property bool armed: root.killPid === modelData.pid

                        width: procList.width
                        height: 24

                        Rectangle {
                            anchors.fill: parent
                            anchors.leftMargin: -4
                            anchors.rightMargin: -4
                            radius: Theme.radiusInner
                            color: prHover.hovered ? Theme.overlay : "transparent"
                        }
                        HoverHandler { id: prHover }

                        Text {
                            anchors.left: parent.left
                            anchors.right: cpuText.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            text: pr.modelData.name
                            elide: Text.ElideRight
                            color: Theme.text
                            font.family: Theme.fontText
                            font.pixelSize: Theme.fontBody
                        }

                        Text {
                            id: cpuText
                            anchors.right: memText.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 48
                            horizontalAlignment: Text.AlignRight
                            text: pr.modelData.cpu.toFixed(1) + "%"
                            color: root.procSort === "cpu" ? Theme.bright : Theme.subtext
                            font.family: Theme.fontText
                            font.pixelSize: Theme.fontBody
                        }

                        Text {
                            id: memText
                            anchors.right: killBtn.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 60
                            horizontalAlignment: Text.AlignRight
                            text: root.kib(pr.modelData.memKb)
                            color: root.procSort === "mem" ? Theme.bright : Theme.subtext
                            font.family: Theme.fontText
                            font.pixelSize: Theme.fontBody
                        }

                        // Only on your own processes: kill as a user can't
                        // touch root's, and a button that silently fails is
                        // worse than none.
                        Rectangle {
                            id: killBtn
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            width: 22
                            height: 20
                            radius: Theme.radiusInner
                            visible: pr.mine
                            color: pr.armed ? Theme.alert
                                : killMouse.containsMouse ? Theme.surface : "transparent"
                            border.width: 1
                            border.color: pr.armed ? Theme.alert
                                : killMouse.containsMouse ? Theme.muted : "transparent"

                            Text {
                                anchors.centerIn: parent
                                // a check to confirm once armed, an x before
                                text: pr.armed ? "󰄬" : "󰅖"
                                color: pr.armed ? Theme.base
                                    : killMouse.containsMouse ? Theme.bright : Theme.muted
                                font.family: Theme.fontIcon
                                font.pixelSize: Theme.fontIconSize
                            }

                            MouseArea {
                                id: killMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.requestKill(pr.modelData.pid)
                            }
                        }
                    }
                }
            }

            Text {
                width: parent.width
                text: root.killPid > 0 ? "Click again to end that process" : ""
                color: Theme.subtext
                font.family: Theme.fontText
                font.pixelSize: Theme.fontSmall
                height: 12
            }
        }

        // ---- right: system, specs, quick links ----
        Column {
            width: root.colWidth
            spacing: 6

            FlyoutHeading { text: "SYSTEM" }

            Info { label: "Kernel";   value: root.kernel }
            Info { label: "Uptime";   value: root.duration(root.uptimeSec) }
            Info { label: "Hostname"; value: root.hostname }
            Info {
                label: "Packages"
                value: root.pkgCount < 0 ? "--" : root.pkgCount + "  (" + root.aurCount + " AUR)"
            }

            Item { width: 1; height: 4 }
            Item {
                width: parent.width
                height: 18

                FlyoutHeading {
                    anchors.left: parent.left
                    anchors.right: copyBtn.left
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: "SPECS"
                }

                Rectangle {
                    id: copyBtn
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: copyLabel.implicitWidth + 16
                    height: 18
                    radius: Theme.radiusInner
                    color: copyMouse.containsMouse ? Theme.overlay : "transparent"
                    border.width: 1
                    border.color: Theme.border

                    Text {
                        id: copyLabel
                        anchors.centerIn: parent
                        text: root.copied ? "Copied" : "Copy"
                        color: root.copied ? Theme.bright : Theme.subtext
                        font.family: Theme.fontText
                        font.pixelSize: Theme.fontSmall
                    }

                    MouseArea {
                        id: copyMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.copySummary()
                    }
                }
            }

            Info { label: "CPU";   value: root.cpuModel || "--" }
            Info {
                label: "GPU"
                value: (root.gpuModel || "--") + (root.gpuDriver ? "  ·  " + root.gpuDriver : "")
                    + (root.mesaVersion ? "  ·  mesa " + root.mesaVersion : "")
            }
            Info { label: "RAM";   value: root.memTotalKb > 0 ? root.kib(root.memTotalKb) : "--" }
            Info { label: "Board"; value: root.board || "--" }

            Repeater {
                model: root.monitors
                Info {
                    required property var modelData
                    label: root.monitors.length > 1 ? "Display " + modelData.name : "Display"
                    value: modelData.width + " × " + modelData.height + "  @" + modelData.hz + "Hz"
                }
            }
            Info { visible: root.monitors.length === 0; label: "Display"; value: "--" }

            Repeater {
                model: root.storage
                Info {
                    required property var modelData
                    label: modelData.tran ? modelData.name + " (" + modelData.tran + ")" : modelData.name
                    value: modelData.model + "  ·  " + modelData.size
                }
            }
            Info { visible: root.storage.length === 0; label: "Storage"; value: "--" }

            Item { width: 1; height: 4 }
            FlyoutHeading { text: "QUICK LINKS" }

            Row {
                width: parent.width
                spacing: 6

                FlyoutChip {
                    text: "hyprland.lua"
                    onClicked: Quickshell.execDetached(["alacritty", "-e", "nvim",
                        Quickshell.env("HOME") + "/.config/hypr/hyprland.lua"])
                }
                FlyoutChip {
                    text: "shell.qml"
                    onClicked: Quickshell.execDetached(["alacritty", "-e", "nvim",
                        Quickshell.env("HOME") + "/.config/quickshell/shell.qml"])
                }
            }
        }
    }
}
