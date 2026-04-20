import QtQuick 2.15
import Quickshell.Io 0.1
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    // ── State ─────────────────────────────────────────────────────────────────
    property int   cpuPct:  0;  property string cpuVal: "—"
    property int   ramPct:  0;  property string ramVal: "—"
    property int   gpuPct:  0;  property string gpuVal: "—"
    property int   vramPct: 0;  property string vramVal: "—"
    property string netUp: "—"; property string netDown: "—"
    property string diskUp: "—";property string diskDown: "—"

    property var _prevCpu:  null
    property var _prevNet:  null
    property var _prevDisk: null

    // ── Sysfs readers ─────────────────────────────────────────────────────────
    function _sysread(path) {
        try {
            const fv = Qt.createQmlObject('import Quickshell.Io 0.1; FileView { path: "' + path + '"; watchChanges: false }', root)
            fv.reload()
            const t = fv.text || ""
            fv.destroy()
            return t.trim()
        } catch(_) { return "" }
    }

    // Read proc files via Process (async, called each tick)
    Process {
        id: tickProc
        command: ["bash", "-c",
            "cat /proc/stat /proc/meminfo /proc/net/dev /proc/diskstats; " +
            "for h in /sys/class/hwmon/hwmon*/name; do echo \"HWMON:$(basename $(dirname $h)):$(cat $h)\"; done; " +
            "for c in /sys/class/drm/card*/device/gpu_busy_percent; do echo \"GPU_BUSY:$(cat $c 2>/dev/null || echo 0)\"; done; " +
            "for c in /sys/class/drm/card*/device/mem_info_vram_used; do echo \"VRAM_USED:$(cat $c 2>/dev/null || echo 0)\"; done; " +
            "for c in /sys/class/drm/card*/device/mem_info_vram_total; do echo \"VRAM_TOTAL:$(cat $c 2>/dev/null || echo 0)\"; done"]
        running: false
        stdout: StdioCollector { id: tickStdio }
        onExited: root._processTick(tickStdio.text)
    }

    function _processTick(raw) {
        const lines = raw.split("\n")
        const now = Date.now()

        // CPU: first line "cpu  ..."
        const cpuLine = lines.find(function(l) { return l.match(/^cpu\s/) })
        if (cpuLine) {
            const f = cpuLine.split(/\s+/).slice(1).map(Number)
            const idle = f[3] + (f[4] || 0)
            const total = f.reduce(function(a,b) { return a+b }, 0)
            if (_prevCpu) {
                const dt = total - _prevCpu.total
                const di = idle  - _prevCpu.idle
                cpuPct = dt === 0 ? 0 : Math.round((1 - di / dt) * 100)
            }
            _prevCpu = { idle, total }
        }
        // CPU temp
        const cpuHwmon = lines.find(function(l) { return /HWMON:.*:(k10temp|coretemp)/.test(l) })
        if (cpuHwmon) {
            const hwmonId = cpuHwmon.split(":")[1]
            const tempLine = lines.find(function(l) { return l.startsWith("TEMP1:" + hwmonId + ":") })
            // fallback: no temp included in this simple batch; show pct only
        }
        cpuVal = cpuPct + "%"

        // RAM
        const memTotal   = _extractMeminfo(lines, "MemTotal")
        const memAvail   = _extractMeminfo(lines, "MemAvailable")
        if (memTotal > 0) {
            const used = memTotal - memAvail
            ramPct = Math.round(used / memTotal * 100)
            ramVal = _fmtBytes(used * 1024)
        }

        // GPU
        const gpuBusy  = _extractTagged(lines, "GPU_BUSY")
        const vramUsed = _extractTagged(lines, "VRAM_USED")
        const vramTot  = _extractTagged(lines, "VRAM_TOTAL")
        if (gpuBusy >= 0)  { gpuPct  = gpuBusy; gpuVal  = gpuBusy + "%" }
        if (vramTot > 0)   { vramPct = Math.round(vramUsed / vramTot * 100); vramVal = _fmtBytes(vramUsed) }

        // Network
        let rx = 0, tx = 0
        for (const l of lines) {
            const m = l.trim().match(/^(\w+):\s+(\d+)\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+\d+\s+(\d+)/)
            if (m && m[1] !== "lo") { rx += parseInt(m[2]); tx += parseInt(m[3]) }
        }
        if (_prevNet) {
            const dt = (now - _prevNet.ts) / 1000
            netDown = "↓ " + _fmtSpeed(Math.max(0, (rx - _prevNet.rx) / dt))
            netUp   = "↑ " + _fmtSpeed(Math.max(0, (tx - _prevNet.tx) / dt))
        }
        _prevNet = { rx, tx, ts: now }

        // Disk (first non-loop, non-partition device)
        let dread = 0, dwrite = 0
        for (const l of lines) {
            const parts = l.trim().split(/\s+/)
            if (parts.length < 14) continue
            const dev = parts[2]
            if (!dev || /\d$/.test(dev) || dev.startsWith("loop")) continue
            dread  = parseInt(parts[5])  * 512
            dwrite = parseInt(parts[9])  * 512
            break
        }
        if (_prevDisk) {
            const dt = (now - _prevDisk.ts) / 1000
            diskDown = "↓ " + _fmtSpeed(Math.max(0, (dread  - _prevDisk.r) / dt))
            diskUp   = "↑ " + _fmtSpeed(Math.max(0, (dwrite - _prevDisk.w) / dt))
        }
        _prevDisk = { r: dread, w: dwrite, ts: now }
    }

    function _extractMeminfo(lines, key) {
        const l = lines.find(function(x) { return x.startsWith(key + ":") })
        if (!l) return 0
        const m = l.match(/(\d+)/)
        return m ? parseInt(m[1]) : 0
    }

    function _extractTagged(lines, tag) {
        const l = lines.find(function(x) { return x.startsWith(tag + ":") })
        if (!l) return 0
        return parseInt(l.split(":")[1]) || 0
    }

    function _fmtBytes(n) {
        if (n >= 1e9) return Math.round(n / 1e9) + " GB"
        if (n >= 1e6) return Math.round(n / 1e6) + " MB"
        if (n >= 1e3) return Math.round(n / 1e3) + " KB"
        return Math.round(n) + " B"
    }

    function _fmtSpeed(n) { return _fmtBytes(n) + "/S" }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: tickProc.running = true
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors { fill: parent; margins: 10 }
        spacing: 8

        Repeater {
            model: [
                { label: "CPU",  pct: root.cpuPct,  val: root.cpuVal  },
                { label: "RAM",  pct: root.ramPct,  val: root.ramVal  },
                { label: "GPU",  pct: root.gpuPct,  val: root.gpuVal  },
                { label: "VRAM", pct: root.vramPct, val: root.vramVal },
            ]
            delegate: Row {
                width: parent.width
                spacing: 10
                Text {
                    text: modelData.label; width: 32
                    font.pixelSize: 10; font.letterSpacing: 1
                    color: Theme.accentColor; verticalAlignment: Text.AlignVCenter; height: 16
                }
                Rectangle {
                    width: parent.width - 32 - valText.width - 20; height: 6
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.rgba(1,1,1,0.1); radius: 3
                    Rectangle {
                        width: parent.width * (modelData.pct / 100); height: parent.height
                        color: Theme.accentColor; radius: parent.radius
                    }
                }
                Text {
                    id: valText; text: modelData.val; width: 70
                    font.pixelSize: 10; color: Theme.textColor
                    horizontalAlignment: Text.AlignRight; verticalAlignment: Text.AlignVCenter; height: 16
                }
            }
        }

        // I/O row
        Row {
            width: parent.width; spacing: 0
            Repeater {
                model: [
                    { label: "NET",  up: root.netUp,  down: root.netDown  },
                    { label: "DISK", up: root.diskUp, down: root.diskDown },
                ]
                delegate: Row {
                    width: parent.width / 2; spacing: 8
                    Text { text: modelData.label; font.pixelSize: 10; font.letterSpacing: 1; color: Theme.accentColor; width: 28 }
                    Text { text: modelData.up;    font.pixelSize: 10; color: Theme.textColor }
                    Text { text: modelData.down;  font.pixelSize: 10; color: Theme.textColor }
                }
            }
        }
    }
}
