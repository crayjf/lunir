import QtQuick 2.15
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    property string hostControllerId: ""

    readonly property color _textColor:   Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property color _mutedText:   Theme.textMuted
    readonly property color _trackColor:  Theme.track
    readonly property color _panelColor:  Theme.surface
    readonly property color _busyColor:   Theme.surfaceHover

    readonly property int preferredHeight: leftCol.implicitHeight
    readonly property real _systemColumnWidth: (mainRow.width - mainRow.spacing * 2) / 3

    // ── Perf state ────────────────────────────────────────────────────────────
    property int    cpuPct:  0;  property string cpuVal:  "—"
    property int    ramPct:  0;  property string ramVal:  "—"
    property int    gpuPct:  0;  property string gpuVal:  "—"
    property int    vramPct: 0;  property string vramVal: "—"
    property string netDown: "—"; property string netUp: "—"
    property var    _prevCpu: null
    property var    _prevNet: null

    // ── Updates state ─────────────────────────────────────────────────────────
    property var    _packages:     []
    property bool   _fetching:     false
    property string _updateStatus: "UPDATES"
    readonly property string _cachePath: Quickshell.dataPath("updates-cache.json")

    // ── Network state ─────────────────────────────────────────────────────────
    readonly property string _protonBinDir: (Quickshell.env("HOME") || "") + "/.local/bin"
    readonly property var _devices: Networking.devices.values

    property var    _fallbackEthIfaces:  []
    property var    _fallbackWifiIfaces: []
    property bool   _vpnConnected: false
    property string _vpnServer:    ""
    property bool   _vpnBusy:      false
    property bool   _autoConnect:  true

    readonly property var _ethIfaces: root._devices
        .filter(function(d) { return root._isRealWiredDevice(d) })
        .map(function(d) { return { name: d.name, connected: d.connected } })
    readonly property var _wifiIfaces: root._devices
        .filter(function(d) { return root._isWifiDevice(d) })
        .map(function(d) {
            const active = d.networks && d.networks.values
                ? d.networks.values.find(function(n) { return n.connected }) : null
            return { name: d.name, connected: d.connected, ssid: active ? active.name : "" }
        })
    readonly property var ethIfaces:  _ethIfaces.length  > 0 ? _ethIfaces  : _fallbackEthIfaces
    readonly property var wifiIfaces: _wifiIfaces.length > 0 ? _wifiIfaces : _fallbackWifiIfaces
    readonly property bool ethernetConnected: ethIfaces.some(function(i) { return i.connected })
    readonly property bool wifiConnected:     wifiIfaces.some(function(i) { return i.connected })
    readonly property string wifiSsid: {
        const a = wifiIfaces.find(function(i) { return i.connected && i.ssid })
        return a ? a.ssid : ""
    }
    readonly property var _netTiles: [
        { key: "ethernet", label: "ETHERNET", connected: root.ethernetConnected,
          detail: root.ethernetConnected ? "Connected" : "Offline", interactive: false },
        { key: "wifi",     label: "WI-FI",    connected: root.wifiConnected,
          detail: root.wifiConnected ? (root.wifiSsid || "Connected") : "Offline", interactive: false },
        { key: "vpn",      label: "VPN",      connected: root._vpnConnected,
          detail: root._vpnBusy ? "Working…" : (root._vpnConnected ? (root._vpnServer || "Connected") : "Offline"),
          interactive: true }
    ]
    readonly property var _wifiTile: root._netTiles.find(function(tile) { return tile.key === "wifi" })
    readonly property var _secondaryNetTiles: root._netTiles.filter(function(tile) { return tile.key !== "wifi" })

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _fmtBytes(n) {
        if (n >= 1e9) return Math.round(n / 1e9) + " GB"
        if (n >= 1e6) return Math.round(n / 1e6) + " MB"
        if (n >= 1e3) return Math.round(n / 1e3) + " KB"
        return Math.round(n) + " B"
    }
    function _fmtSpeed(n) { return _fmtBytes(n) + "/S" }

    function _extractMeminfo(lines, key) {
        const l = lines.find(function(x) { return x.startsWith(key + ":") })
        return l ? (parseInt((l.match(/(\d+)/) || [])[1]) || 0) : 0
    }

    function _extractGpuMetrics(lines) {
        const metrics = []
        for (const line of lines) {
            if (!line.startsWith("GPU_METRIC:")) continue
            const parts = line.split(":")
            if (parts.length < 5) continue
            metrics.push({ busy: parseInt(parts[2]) || 0, used: parseInt(parts[3]) || 0, total: parseInt(parts[4]) || 0 })
        }
        if (!metrics.length) return null
        return metrics.sort(function(a, b) { return (b.total - a.total) || (b.busy - a.busy) })[0]
    }
    function _extractNetCounters(lines) {
        let rx = 0, tx = 0
        for (const line of lines) {
            if (line.indexOf(":") < 0) continue
            const parts = line.split(":")
            if (parts.length < 2) continue
            const iface = parts[0].trim()
            if (!iface || iface === "lo") continue
            const stats = parts[1].trim().split(/\s+/)
            if (stats.length < 9) continue
            rx += parseInt(stats[0]) || 0
            tx += parseInt(stats[8]) || 0
        }
        return { rx, tx }
    }

    function _isWifiDevice(d)      { return d && d.type === DeviceType.Wifi }
    function _isRealWiredDevice(d) {
        if (!d || !d.name || d.name === "lo") return false
        if (root._isWifiDevice(d)) return false
        if (d.name.startsWith("proton") || d.name.startsWith("ipv6leak")) return false
        return true
    }
    function _enableWifiScanning() {
        for (const d of root._devices)
            if (root._isWifiDevice(d) && d.scannerEnabled !== true) d.scannerEnabled = true
    }
    function _fetchFallbackSsid(iface) { fallbackSsidProc.iface = iface; fallbackSsidProc.running = true }
    function _toggleVpn() {
        if (root._vpnBusy) return
        root._vpnBusy = true; vpnBusyTimeout.restart()
        if (root._vpnConnected) vpnDiscProc.running = true
        else vpnConnProc.running = true
    }
    function _hideHost() { if (root.hostControllerId) ModuleControllers.hide(root.hostControllerId) }
    function _packageName(entry) {
        const m = String(entry || "").match(/^(\S+)/)
        return m ? m[1] : String(entry || "")
    }
    function _fetchUpdates() {
        if (_fetching) return
        _fetching = true; _updateStatus = "CHECKING…"; checkProc.running = true
    }

    // ── Perf tick ─────────────────────────────────────────────────────────────
    Process {
        id: tickProc
        command: ["bash", "-c",
            "cat /proc/stat /proc/meminfo /proc/net/dev; " +
            "for h in /sys/class/hwmon/hwmon*/name; do echo \"HWMON:$(basename $(dirname $h)):$(cat $h)\"; done; " +
            "shopt -s nullglob; " +
            "for d in /sys/class/drm/card[0-9]/device; do " +
            "busy=$(cat \"$d/gpu_busy_percent\" 2>/dev/null || echo -1); " +
            "used=$(cat \"$d/mem_info_vram_used\" 2>/dev/null || cat \"$d/mem_info_vis_vram_used\" 2>/dev/null || echo 0); " +
            "total=$(cat \"$d/mem_info_vram_total\" 2>/dev/null || cat \"$d/mem_info_vis_vram_total\" 2>/dev/null || echo 0); " +
            "echo \"GPU_METRIC:$(basename $(dirname $d)):$busy:$used:$total\"; done"]
        running: false
        stdout: StdioCollector { id: tickStdio }
        onExited: {
            const lines = tickStdio.text.split("\n")
            const now = Date.now()
            const cpuLine = lines.find(function(l) { return l.match(/^cpu\s/) })
            if (cpuLine) {
                const f = cpuLine.split(/\s+/).slice(1).map(Number)
                const idle = f[3] + (f[4] || 0)
                const total = f.reduce(function(a, b) { return a + b }, 0)
                if (root._prevCpu) {
                    const dt = total - root._prevCpu.total, di = idle - root._prevCpu.idle
                    root.cpuPct = dt === 0 ? 0 : Math.round((1 - di / dt) * 100)
                }
                root._prevCpu = { idle, total }
            }
            root.cpuVal = root.cpuPct + "%"
            const memTotal = root._extractMeminfo(lines, "MemTotal")
            const memAvail = root._extractMeminfo(lines, "MemAvailable")
            if (memTotal > 0) {
                const used = memTotal - memAvail
                root.ramPct = Math.round(used / memTotal * 100)
                root.ramVal = root._fmtBytes(used * 1024)
            }
            const gpu = root._extractGpuMetrics(lines)
            if (gpu) {
                if (gpu.busy >= 0) { root.gpuPct = gpu.busy; root.gpuVal = gpu.busy + "%" }
                if (gpu.total > 0) { root.vramPct = Math.round(gpu.used / gpu.total * 100); root.vramVal = root._fmtBytes(gpu.used) }
            }
            const counters = root._extractNetCounters(lines)
            const rx = counters.rx, tx = counters.tx
            if (root._prevNet) {
                const dt = (now - root._prevNet.ts) / 1000
                root.netDown = "↓ " + root._fmtSpeed(Math.max(0, (rx - root._prevNet.rx) / dt))
                root.netUp   = "↑ " + root._fmtSpeed(Math.max(0, (tx - root._prevNet.tx) / dt))
            }
            root._prevNet = { rx, tx, ts: now }
        }
    }

    Timer { interval: 1000; repeat: true; running: root.visible; triggeredOnStart: true; onTriggered: tickProc.running = true }

    // ── Network processes ─────────────────────────────────────────────────────
    Timer { id: vpnBusyTimeout; interval: 30000; repeat: false; onTriggered: root._vpnBusy = false }

    Process {
        id: ifaceFallbackProc
        command: ["sh", "-c",
            "ls /sys/class/net/ | while read i; do " +
            "state=$(cat /sys/class/net/$i/operstate 2>/dev/null || echo unknown); echo \"$i:$state\"; done"]
        running: false
        stdout: StdioCollector { id: ifaceFallbackStdio }
        onExited: {
            const lines = ifaceFallbackStdio.text.trim().split("\n")
            const eth = [], wifi = []
            for (const line of lines) {
                const parts = line.split(":")
                if (parts.length < 2) continue
                const name = parts[0].trim(), state = parts[1].trim()
                if (!name || name === "lo" || name.startsWith("proton") || name.startsWith("ipv6leak")) continue
                if (name.startsWith("wl")) wifi.push({ name, connected: state === "up", ssid: "" })
                else eth.push({ name, connected: state === "up" })
            }
            root._fallbackEthIfaces = eth
            root._fallbackWifiIfaces = wifi
            for (const iface of wifi) if (iface.connected) root._fetchFallbackSsid(iface.name)
        }
    }

    Process {
        id: fallbackSsidProc
        property string iface: ""
        command: ["nmcli", "-g", "GENERAL.CONNECTION", "device", "show", fallbackSsidProc.iface]
        running: false
        stdout: StdioCollector { id: fallbackSsidStdio }
        onExited: {
            const ssid = fallbackSsidStdio.text.trim()
            const idx = root._fallbackWifiIfaces.findIndex(function(i) { return i.name === fallbackSsidProc.iface })
            if (idx < 0) return
            const updated = root._fallbackWifiIfaces.slice()
            updated[idx] = Object.assign({}, updated[idx], { ssid: ssid === "--" ? "" : ssid })
            root._fallbackWifiIfaces = updated
        }
    }

    Process {
        id: vpnCheckProc
        command: ["bash", "-lc",
            "nmcli -t -f NAME,DEVICE connection show --active | grep ':proton0$' | cut -d: -f1"]
        running: false
        stdout: StdioCollector { id: vpnCheckStdio }
        onExited: {
            const out = vpnCheckStdio.text.trim()
            const connected = out.length > 0
            if (connected !== root._vpnConnected) root._vpnConnected = connected
            if (out !== root._vpnServer) root._vpnServer = out
            if (root._autoConnect && !root._vpnConnected) {
                root._autoConnect = false; root._vpnBusy = true
                vpnBusyTimeout.restart(); vpnConnProc.running = true
            } else { root._autoConnect = false }
        }
    }

    Process {
        id: vpnConnProc
        command: ["bash", "-lc",
            "export XDG_RUNTIME_DIR=/run/user/$(id -u); " +
            "export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus; " +
            "\"" + root._protonBinDir + "/protonvpn-connect\""]
        running: false
        onExited: { vpnBusyTimeout.stop(); root._vpnBusy = false; vpnCheckProc.running = true }
    }

    Process {
        id: vpnDiscProc
        command: ["bash", "-lc",
            "export XDG_RUNTIME_DIR=/run/user/$(id -u); " +
            "export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus; " +
            "\"" + root._protonBinDir + "/protonvpn-disconnect\""]
        running: false
        onExited: { vpnBusyTimeout.stop(); root._vpnBusy = false; vpnCheckProc.running = true }
    }

    Timer {
        interval: 10000; repeat: true; running: root.visible; triggeredOnStart: false
        onTriggered: { root._enableWifiScanning(); ifaceFallbackProc.running = true; vpnCheckProc.running = true }
    }

    // ── Updates processes ─────────────────────────────────────────────────────
    Process {
        id: readCacheProc
        command: ["cat", root._cachePath]
        running: false
        stdout: StdioCollector { id: readCacheStdio }
        onExited: (code) => {
            if (code !== 0) return
            try { const d = JSON.parse(readCacheStdio.text); if (Array.isArray(d)) root._packages = d } catch (_) {}
        }
    }

    Process {
        id: saveCacheProc
        property string content: ""
        command: ["sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"",
            "sh", root._cachePath, saveCacheProc.content]
        running: false
    }

    Process {
        id: checkProc
        command: ["checkupdates"]
        running: false
        stdout: StdioCollector { id: checkStdio }
        onExited: {
            root._fetching = false
            root._packages = checkStdio.text.trim().split("\n").filter(function(l) { return l.trim() })
            root._updateStatus = "UPDATES"
            saveCacheProc.content = JSON.stringify(root._packages)
            saveCacheProc.running = true
        }
    }

    Process {
        id: cleanupProc
        command: ["ghostty", "-e", "fish", "-lc",
            "clean-arch; echo; read -P 'Press enter to close...'"]
        running: false
        onExited: root._hideHost()
    }

    Process {
        id: updateProc
        command: ["ghostty", "-e", "sh", "-c", "paru -Syu; echo; read -p 'Press enter to close...'"]
        running: false
        onExited: { root._hideHost(); root._fetchUpdates() }
    }

    Timer { interval: 3600000; repeat: true; running: true; onTriggered: root._fetchUpdates() }

    Component.onCompleted: {
        root._enableWifiScanning()
        ifaceFallbackProc.running = true
        vpnCheckProc.running = true
        readCacheProc.running = true
        root._fetchUpdates()
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Row {
        id: mainRow
        anchors.fill: parent
        spacing: 10

        // ── Left column ───────────────────────────────────────────────────────
        Column {
            id: leftCol
            width: root._systemColumnWidth * 2 + parent.spacing
            spacing: 10

            // ── Metric cards: CPU · RAM · GPU · VRAM ─────────────────────────
            Grid {
                width: parent.width
                columns: 2
                rowSpacing: 10
                columnSpacing: 10

                Repeater {
                    model: [
                        { label: "CPU",  pct: root.cpuPct,  val: root.cpuVal  },
                        { label: "RAM",  pct: root.ramPct,  val: root.ramVal  },
                        { label: "GPU",  pct: root.gpuPct,  val: root.gpuVal  },
                        { label: "VRAM", pct: root.vramPct, val: root.vramVal },
                    ]
                    delegate: Rectangle {
                        width: (parent.width - parent.columnSpacing) / parent.columns
                        height: 52
                        radius: 16
                        color: root._panelColor

                        Column {
                            anchors { fill: parent; margins: 10 }
                            spacing: 6

                            Item {
                                width: parent.width
                                height: 14
                                Text {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label; font.family: Theme.fontFamily
                                    font.pixelSize: 9; font.letterSpacing: 1.6; color: root._mutedText
                                }
                                Text {
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.val; font.family: Theme.fontFamily
                                    font.pixelSize: 10; font.bold: true; color: root._textColor
                                    horizontalAlignment: Text.AlignRight
                                }
                            }

                            Item {
                                width: parent.width
                                height: 12
                                Rectangle {
                                    width: parent.width; height: 8; anchors.verticalCenter: parent.verticalCenter
                                    radius: 4; color: root._trackColor
                                    Rectangle {
                                        width: Math.max(8, parent.width * (Math.max(0, Math.min(100, modelData.pct)) / 100))
                                        height: parent.height; topLeftRadius: 4; bottomLeftRadius: 4
                                        topRightRadius: 2; bottomRightRadius: 2; color: root._accentColor
                                    }
                                }
                                Rectangle {
                                    width: 3; height: 14; radius: 1.5; anchors.verticalCenter: parent.verticalCenter
                                    x: Math.max(0, Math.min(parent.width - width,
                                        parent.width * (Math.max(0, Math.min(100, modelData.pct)) / 100) - width / 2 + 4))
                                    color: Theme.text
                                }
                            }
                        }
                    }
                }
            }

            // ── NET speed ─────────────────────────────────────────────────────
            Row {
                width: parent.width
                spacing: 10

                Rectangle {
                    width: (parent.width - parent.spacing) / 2
                    height: 48
                    radius: 16
                    color: root._panelColor

                    Column {
                        anchors { fill: parent; margins: 10 }
                        spacing: 4

                        Item {
                            width: parent.width
                            height: 14
                            Text {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - netStatus.width - 4
                                text: "NET"; font.family: Theme.fontFamily
                                font.pixelSize: 9; font.letterSpacing: 1.6; color: root._mutedText
                                elide: Text.ElideRight
                            }
                            Text {
                                id: netStatus
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: "I/O"
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true
                                color: root._textColor; horizontalAlignment: Text.AlignRight
                            }
                        }

                        Text {
                            width: parent.width
                            text: root.netDown + "   " + root.netUp
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: root._textColor
                            elide: Text.ElideRight
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - parent.spacing) / 2
                    height: 48
                    radius: 16
                    color: root._panelColor

                    Column {
                        anchors { fill: parent; margins: 10 }
                        spacing: 4

                        Item {
                            width: parent.width
                            height: 14
                            Text {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - wifiStatus.width - 4
                                text: root._wifiTile ? root._wifiTile.label : "WI-FI"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9; font.letterSpacing: 1.4; color: root._mutedText
                                elide: Text.ElideRight
                            }
                            Text {
                                id: wifiStatus
                                anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                text: root._wifiTile && root._wifiTile.connected ? "ON" : "OFF"
                                font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true
                                color: root._textColor; horizontalAlignment: Text.AlignRight
                            }
                        }

                        Text {
                            width: parent.width
                            text: root._wifiTile ? root._wifiTile.detail : "Offline"
                            font.family: Theme.fontFamily; font.pixelSize: 9
                            color: root._textColor; elide: Text.ElideRight
                        }
                    }
                }
            }

            // ── Network status: Ethernet · VPN ────────────────────────────────
            Row {
                width: parent.width
                spacing: 10

                Repeater {
                    model: root._secondaryNetTiles
                    delegate: Rectangle {
                        required property var modelData
                        width: (parent.width - parent.spacing) / 2
                        height: 48
                        radius: 16
                        color: root._panelColor

                        Column {
                            anchors { fill: parent; margins: 10 }
                            spacing: 4

                            Item {
                                width: parent.width
                                height: 14
                                Text {
                                    anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - tileStatus.width - 4
                                    text: modelData.label; font.family: Theme.fontFamily
                                    font.pixelSize: 9; font.letterSpacing: 1.4; color: root._mutedText
                                    elide: Text.ElideRight
                                }
                                Text {
                                    id: tileStatus
                                    anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.connected ? "ON" : "OFF"
                                    font.family: Theme.fontFamily; font.pixelSize: 10; font.bold: true
                                    color: root._textColor; horizontalAlignment: Text.AlignRight
                                }
                            }

                            Text {
                                width: parent.width; text: modelData.detail
                                font.family: Theme.fontFamily; font.pixelSize: 9
                                color: root._textColor; elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: modelData.interactive
                            cursorShape: modelData.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root._toggleVpn()
                        }
                    }
                }
            }
        }

        // ── Updates (full right column) ───────────────────────────────────────
        Rectangle {
            width: root._systemColumnWidth
            height: leftCol.implicitHeight
            radius: 16
            color: root._panelColor

            Item {
                anchors { fill: parent; margins: 10 }

                Item {
                    id: updHeader
                    anchors { left: parent.left; right: parent.right; top: parent.top }
                    height: 14

                    Text {
                        anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                        text: "UPDATES"; font.family: Theme.fontFamily
                        font.pixelSize: 9; font.letterSpacing: 1.6; color: root._mutedText
                    }
                    MouseArea {
                        id: updCleanupMA
                        anchors { right: updRefreshMA.left; rightMargin: 6; top: parent.top; bottom: parent.bottom }
                        width: 18; hoverEnabled: true
                        onClicked: { root._hideHost(); cleanupProc.running = true }
                    }
                    Text {
                        anchors.right: updCleanupMA.right; anchors.verticalCenter: parent.verticalCenter
                        text: "✦"; font.family: Theme.fontFamily; font.pixelSize: 12
                        color: updCleanupMA.containsMouse ? root._textColor
                            : Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.72)
                    }
                    MouseArea {
                        id: updRefreshMA
                        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
                        width: 18; hoverEnabled: true
                        onClicked: root._fetchUpdates()
                    }
                    Text {
                        anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                        text: "↻"; font.family: Theme.fontFamily; font.pixelSize: 12
                        color: updRefreshMA.containsMouse ? root._textColor
                            : Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.72)
                    }
                }

                Item {
                    anchors { left: parent.left; right: parent.right; top: updHeader.bottom; topMargin: 6; bottom: updButton.top; bottomMargin: 6 }
                    clip: true

                    Text {
                        anchors.centerIn: parent; visible: root._fetching
                        text: "CHECKING…"; font.family: Theme.fontFamily; font.pixelSize: 9; color: root._mutedText
                    }
                    Text {
                        anchors.centerIn: parent; visible: !root._fetching && root._packages.length === 0
                        text: "UP TO DATE"; font.family: Theme.fontFamily; font.pixelSize: 9; color: root._mutedText
                    }
                    Column {
                        width: parent.width; spacing: 2
                        visible: !root._fetching && root._packages.length > 0
                        Repeater {
                            model: root._packages.slice(0, 20)
                            Text {
                                width: parent.width; text: root._packageName(modelData)
                                font.family: Theme.fontFamily; font.pixelSize: 9
                                color: root._textColor; elide: Text.ElideRight
                            }
                        }
                    }
                }

                Rectangle {
                    id: updButton
                    anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                    height: 20; radius: 10
                    color: updMouse.containsMouse && root._packages.length > 0
                        ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.30)
                        : root._packages.length > 0
                            ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.18)
                            : Theme.surfaceRaised
                    Text {
                        anchors.centerIn: parent
                        text: root._packages.length > 0 ? (root._packages.length + " PKGS") : "✓"
                        font.family: Theme.fontFamily; font.pixelSize: 8; font.letterSpacing: 1.2
                        color: root._packages.length > 0 ? root._textColor
                            : Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.65)
                    }
                    MouseArea {
                        id: updMouse; anchors.fill: parent; hoverEnabled: true
                        enabled: root._packages.length > 0
                        onClicked: { root._hideHost(); updateProc.running = true }
                    }
                }
            }
        }
    }
}
