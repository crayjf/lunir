import QtQuick 2.15
import QtQuick.Shapes 1.15
import QtQuick.Window 2.15
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
    readonly property color _okColor:     Qt.rgba(0.314, 0.98, 0.482, 0.65)

    onWifiConnectedChanged: {
        if (root._wifiBusy && root.wifiConnected) {
            wifiBusyTimeout.stop(); wifiPollTimer.stop(); root._wifiBusy = false
        }
    }

    readonly property int preferredHeight: systemCol.implicitHeight

    // ── Perf state ────────────────────────────────────────────────────────────
    property int    cpuPct:  0;  property string cpuVal:  "—"
    property int    ramPct:  0;  property string ramVal:  "—"
    property int    gpuPct:  0;  property string gpuVal:  "—"
    property int    vramPct: 0;  property string vramVal: "—"
    property string netDown: "—"; property string netUp: "—"
    property real   _netDownBps: 0; property real _netUpBps: 0
    property var    _prevCpu: null
    property var    _prevNet: null

    // ── Updates state ─────────────────────────────────────────────────────────
    property var    _packages:     []
    property bool   _fetching:     false
    property bool   _updating:     false
    property string _updateStatus: "UPDATES"
    readonly property string _cachePath: Quickshell.dataPath("updates-cache.json")
    readonly property string _updateDonePath: Quickshell.dataPath("update-complete")
    property string _updateToken: ""

    // ── Network state ─────────────────────────────────────────────────────────
    readonly property string _protonBinDir: (Quickshell.env("HOME") || "") + "/.local/bin"
    readonly property var _devices: Networking.devices.values

    property var    _fallbackWifiIfaces: []
    property bool   _wifiBusy:     false
    property bool   _vpnConnected: false
    property string _vpnServer:    ""
    property string _vpnError:     ""
    property bool   _vpnBusy:      false
    property bool   _autoConnect:  true

    readonly property var _wifiIfaces: root._devices
        .filter(function(d) { return root._isWifiDevice(d) })
        .map(function(d) {
            const active = d.networks && d.networks.values
                ? d.networks.values.find(function(n) { return n.connected }) : null
            return { name: d.name, connected: d.connected, ssid: active ? active.name : "" }
        })
    readonly property var wifiIfaces: _wifiIfaces.length > 0 ? _wifiIfaces : _fallbackWifiIfaces
    readonly property bool wifiConnected:     wifiIfaces.some(function(i) { return i.connected })
    readonly property string wifiSsid: {
        const a = wifiIfaces.find(function(i) { return i.connected && i.ssid })
        return a ? a.ssid : ""
    }
    readonly property var _netTiles: [
        { key: "vpn",  icon: "", connected: root._vpnConnected,
          detail: root._vpnBusy ? "Working…" : (root._vpnConnected
              ? (root._vpnServer.replace("VPN","").replace(/#.*/,"").trim() || "Connected")
              : (root._vpnError || "Off")),
          interactive: true, singleLine: true },
        { key: "wifi", icon: "", connected: root.wifiConnected,
          detail: root._wifiBusy ? "Working…" : (root.wifiConnected ? (root.wifiSsid || "Connected") : "Off"),
          interactive: true, singleLine: true }
    ]

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _fmtBytes(n) {
        if (n >= 1e9) return Math.round(n / 1e9) + " GB"
        if (n >= 1e6) return Math.round(n / 1e6) + " MB"
        if (n >= 1e3) return Math.round(n / 1e3) + " KB"
        return Math.round(n) + " B"
    }
    function _shQuote(value) {
        return "'" + String(value || "").replace(/'/g, "'\"'\"'") + "'"
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
            if (iface.startsWith("proton") || iface.startsWith("ipv6leak")) continue
            if (iface.startsWith("tun") || iface.startsWith("wg")) continue
            if (iface.startsWith("docker") || iface.startsWith("virbr") || iface.startsWith("veth")) continue
            const stats = parts[1].trim().split(/\s+/)
            if (stats.length < 9) continue
            rx += parseInt(stats[0]) || 0
            tx += parseInt(stats[8]) || 0
        }
        return { rx, tx }
    }

    function _isWifiDevice(d) { return d && d.type === DeviceType.Wifi }
    function _enableWifiScanning() {
        for (const d of root._devices)
            if (root._isWifiDevice(d) && d.scannerEnabled !== true) d.scannerEnabled = true
    }
    function _fetchFallbackSsid(iface) { fallbackSsidProc.iface = iface; fallbackSsidProc.running = true }
    function _toggleWifi() {
        if (root._wifiBusy) return
        root._wifiBusy = true; wifiBusyTimeout.restart()
        wifiToggleProc.enable = !root.wifiConnected; wifiToggleProc.running = true
    }
    function _toggleVpn() {
        if (root._vpnBusy) return
        root._vpnError = ""
        root._vpnBusy = true; vpnBusyTimeout.restart()
        if (root._vpnConnected) vpnDiscProc.running = true
        else vpnConnProc.running = true
    }
    function _vpnErrorText(output) {
        const text = String(output || "").replace(/\s+/g, " ").trim()
        if (!text) return "Failed"
        if (/Authentication required/i.test(text) || /sign in/i.test(text)) return "Sign in required"
        if (/network manager/i.test(text) && /not running|unavailable/i.test(text)) return "NetworkManager unavailable"
        return text
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
    function _startUpdate() {
        if (root._updating) return
        root._updating = true
        root._updateToken = Date.now().toString() + "-" + Math.random().toString(36).slice(2)
        updateWatchTimer.restart()
        updateProc.running = true
        root._hideHost()
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
                const downBps = Math.max(0, (rx - root._prevNet.rx) / dt)
                const upBps   = Math.max(0, (tx - root._prevNet.tx) / dt)
                root.netDown    = "↓ " + root._fmtSpeed(downBps)
                root.netUp      = "↑ " + root._fmtSpeed(upBps)
                root._netDownBps = downBps
                root._netUpBps   = upBps
            }
            root._prevNet = { rx, tx, ts: now }
        }
    }

    Timer { interval: 1000; repeat: true; running: root.visible; triggeredOnStart: true; onTriggered: tickProc.running = true }

    // ── Network processes ─────────────────────────────────────────────────────
    Timer { id: wifiBusyTimeout; interval: 10000; repeat: false; onTriggered: { root._wifiBusy = false; wifiPollTimer.stop() } }
    Timer { id: vpnBusyTimeout;  interval: 30000; repeat: false; onTriggered: root._vpnBusy  = false }
    Timer { id: wifiPollTimer; interval: 2000; repeat: true; running: false; onTriggered: { root._enableWifiScanning(); ifaceFallbackProc.running = true } }

    Process {
        id: wifiToggleProc
        property bool enable: false
        command: ["nmcli", "radio", "wifi", wifiToggleProc.enable ? "on" : "off"]
        running: false
        onExited: {
            if (wifiToggleProc.enable) {
                root._enableWifiScanning()
                ifaceFallbackProc.running = true
                wifiPollTimer.start()
            } else {
                wifiBusyTimeout.stop()
                root._wifiBusy = false
            }
        }
    }

    Process {
        id: ifaceFallbackProc
        command: ["sh", "-c",
            "ls /sys/class/net/ | while read i; do " +
            "state=$(cat /sys/class/net/$i/operstate 2>/dev/null || echo unknown); echo \"$i:$state\"; done"]
        running: false
        stdout: StdioCollector { id: ifaceFallbackStdio }
        onExited: {
            const lines = ifaceFallbackStdio.text.trim().split("\n")
            const wifi = []
            for (const line of lines) {
                const parts = line.split(":")
                if (parts.length < 2) continue
                const name = parts[0].trim(), state = parts[1].trim()
                if (!name || name === "lo" || name.startsWith("proton") || name.startsWith("ipv6leak")) continue
                if (name.startsWith("wl")) wifi.push({ name, connected: state === "up", ssid: "" })
            }
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
            "nmcli -t -f NAME,TYPE,DEVICE connection show --active | " +
            "awk -F: 'BEGIN{IGNORECASE=1} " +
            "($2 ~ /^(vpn|wireguard)$/ || $1 ~ /proton/ || $3 ~ /^(proton|pvpn|wg|tun)/) { print $1; exit }'"]
        running: false
        stdout: StdioCollector { id: vpnCheckStdio }
        onExited: {
            const out = vpnCheckStdio.text.trim()
            const connected = out.length > 0
            if (connected !== root._vpnConnected) root._vpnConnected = connected
            if (out !== root._vpnServer) root._vpnServer = out
            if (connected && root._vpnError) root._vpnError = ""
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
            "protonvpn connect 2>&1"]
        stdout: StdioCollector { id: vpnConnStdio }
        onExited: (code) => {
            vpnBusyTimeout.stop()
            root._vpnBusy = false
            if (code !== 0) root._vpnError = root._vpnErrorText(vpnConnStdio.text)
            vpnCheckProc.running = true
        }
        running: false
    }

    Process {
        id: vpnDiscProc
        command: ["bash", "-lc",
            "export XDG_RUNTIME_DIR=/run/user/$(id -u); " +
            "export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus; " +
            "protonvpn disconnect 2>&1"]
        running: false
        stdout: StdioCollector { id: vpnDiscStdio }
        onExited: (code) => {
            vpnBusyTimeout.stop()
            root._vpnBusy = false
            if (code !== 0) root._vpnError = root._vpnErrorText(vpnDiscStdio.text)
            else root._vpnError = ""
            vpnCheckProc.running = true
        }
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
        id: readUpdateDoneProc
        command: ["cat", root._updateDonePath]
        running: false
        stdout: StdioCollector { id: readUpdateDoneStdio }
        onExited: (code) => {
            if (code !== 0) return
            if (readUpdateDoneStdio.text.trim() !== root._updateToken) return
            updateWatchTimer.stop()
            root._updating = false
            root._packages = []
            saveCacheProc.content = "[]"
            saveCacheProc.running = true
            root._fetchUpdates()
        }
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
        id: updateProc
        property string script: {
            const donePath = root._shQuote(root._updateDonePath)
            const token = root._shQuote(root._updateToken)
            return "mkdir -p (dirname " + donePath + "); " +
                "paru -Syu; " +
                "set update_status $status; " +
                "clean-arch; " +
                "printf %s " + token + " > " + donePath + "; " +
                "echo; read -P 'Press enter to close...'; " +
                "exit $update_status"
        }
        command: ["ghostty", "-e", "fish", "-lc",
            updateProc.script]
        running: false
        onExited: {
            if (!root._updating || readUpdateDoneProc.running) return
            readUpdateDoneProc.running = true
        }
    }

    Process {
        id: nethogProc
        command: ["ghostty", "-e", "nethogs"]
        running: false
    }

    Process {
        id: btopProc
        command: ["ghostty", "-e", "btop"]
        running: false
    }

    Process {
        id: nvtopProc
        command: ["ghostty", "-e", "nvtop"]
        running: false
    }

    Timer { interval: 3600000; repeat: true; running: true; onTriggered: root._fetchUpdates() }
    Timer {
        id: updateWatchTimer
        interval: 2000
        repeat: true
        running: false
        onTriggered: {
            if (!root._updating || readUpdateDoneProc.running) return
            readUpdateDoneProc.running = true
        }
    }

    Component.onCompleted: {
        root._enableWifiScanning()
        ifaceFallbackProc.running = true
        vpnCheckProc.running = true
        readCacheProc.running = true
        root._fetchUpdates()
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        id: systemCol
        anchors.fill: parent
        spacing: 10

        // ── Row 1: 6 circles ─────────────────────────────────────────────────
        // NOT USED — kept for potential future use, not displayed
        Row {
            id: circleRow
            visible: false
            width: parent.width
            spacing: 10

            // ── CPU ──────────────────────────────────────────────────────────
            Item {
                width: (parent.width - parent.spacing * 5) / 6; height: 52
                Rectangle { width: 36; height: 36; radius: 18; anchors.centerIn: parent; color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5); visible: cpuMA.containsMouse }
                Shape {
                    anchors.centerIn: parent; width: 44; height: 44
                    ShapePath { strokeColor: root._trackColor; strokeWidth: 4; fillColor: "transparent"; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: 0; sweepAngle: 360 } }
                    ShapePath { strokeColor: root._accentColor; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: -90; sweepAngle: Math.max(0, 360 * root.cpuPct / 100) } }
                }
                Text { anchors.centerIn: parent; text: "CPU"; font.family: Theme.fontFamily; font.pixelSize: 9; font.letterSpacing: 1.6; color: root._mutedText }
                MouseArea { id: cpuMA; anchors.fill: parent; hoverEnabled: true; onClicked: { root._hideHost(); btopProc.running = true } }
            }

            // ── RAM ──────────────────────────────────────────────────────────
            Item {
                width: (parent.width - parent.spacing * 5) / 6; height: 52
                Rectangle { width: 36; height: 36; radius: 18; anchors.centerIn: parent; color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5); visible: ramMA.containsMouse }
                Shape {
                    anchors.centerIn: parent; width: 44; height: 44
                    ShapePath { strokeColor: root._trackColor; strokeWidth: 4; fillColor: "transparent"; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: 0; sweepAngle: 360 } }
                    ShapePath { strokeColor: root._accentColor; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: -90; sweepAngle: Math.max(0, 360 * root.ramPct / 100) } }
                }
                Text { anchors.centerIn: parent; text: "RAM"; font.family: Theme.fontFamily; font.pixelSize: 9; font.letterSpacing: 1.6; color: root._mutedText }
                MouseArea { id: ramMA; anchors.fill: parent; hoverEnabled: true; onClicked: { root._hideHost(); btopProc.running = true } }
            }

            // ── GPU ──────────────────────────────────────────────────────────
            Item {
                width: (parent.width - parent.spacing * 5) / 6; height: 52
                Rectangle { width: 36; height: 36; radius: 18; anchors.centerIn: parent; color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5); visible: gpuMA.containsMouse }
                Shape {
                    anchors.centerIn: parent; width: 44; height: 44
                    ShapePath { strokeColor: root._trackColor; strokeWidth: 4; fillColor: "transparent"; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: 0; sweepAngle: 360 } }
                    ShapePath { strokeColor: root._accentColor; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: -90; sweepAngle: Math.max(0, 360 * root.gpuPct / 100) } }
                }
                Text { anchors.centerIn: parent; text: "GPU"; font.family: Theme.fontFamily; font.pixelSize: 9; font.letterSpacing: 1.6; color: root._mutedText }
                MouseArea { id: gpuMA; anchors.fill: parent; hoverEnabled: true; onClicked: { root._hideHost(); nvtopProc.running = true } }
            }

            // ── VRAM ─────────────────────────────────────────────────────────
            Item {
                width: (parent.width - parent.spacing * 5) / 6; height: 52
                Rectangle { width: 36; height: 36; radius: 18; anchors.centerIn: parent; color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5); visible: vramMA.containsMouse }
                Shape {
                    anchors.centerIn: parent; width: 44; height: 44
                    ShapePath { strokeColor: root._trackColor; strokeWidth: 4; fillColor: "transparent"; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: 0; sweepAngle: 360 } }
                    ShapePath { strokeColor: root._accentColor; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: -90; sweepAngle: Math.max(0, 360 * root.vramPct / 100) } }
                }
                Text { anchors.centerIn: parent; text: "VRM"; font.family: Theme.fontFamily; font.pixelSize: 9; font.letterSpacing: 1.6; color: root._mutedText }
                MouseArea { id: vramMA; anchors.fill: parent; hoverEnabled: true; onClicked: { root._hideHost(); nvtopProc.running = true } }
            }

            // ── NDO ──────────────────────────────────────────────────────────
            Item {
                width: (parent.width - parent.spacing * 5) / 6; height: 52
                Rectangle { width: 36; height: 36; radius: 18; anchors.centerIn: parent; color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5); visible: ndoMA.containsMouse }
                Shape {
                    anchors.centerIn: parent; width: 44; height: 44
                    ShapePath { strokeColor: root._trackColor; strokeWidth: 4; fillColor: "transparent"; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: 0; sweepAngle: 360 } }
                    ShapePath { strokeColor: root._accentColor; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: -90; sweepAngle: Math.min(1.0, root._netDownBps / (12.5 * 1024 * 1024)) * 360 } }
                }
                Text { anchors.centerIn: parent; text: "NDO"; font.family: Theme.fontFamily; font.pixelSize: 9; font.letterSpacing: 1.6; color: root._mutedText }
                MouseArea { id: ndoMA; anchors.fill: parent; hoverEnabled: true; onClicked: { root._hideHost(); nethogProc.running = true } }
            }

            // ── NUP ──────────────────────────────────────────────────────────
            Item {
                width: (parent.width - parent.spacing * 5) / 6; height: 52
                Rectangle { width: 36; height: 36; radius: 18; anchors.centerIn: parent; color: Qt.rgba(Theme.surface.r, Theme.surface.g, Theme.surface.b, 0.5); visible: nupMA.containsMouse }
                Shape {
                    anchors.centerIn: parent; width: 44; height: 44
                    ShapePath { strokeColor: root._trackColor; strokeWidth: 4; fillColor: "transparent"; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: 0; sweepAngle: 360 } }
                    ShapePath { strokeColor: root._accentColor; strokeWidth: 4; fillColor: "transparent"; capStyle: ShapePath.RoundCap; PathAngleArc { centerX: 22; centerY: 22; radiusX: 18; radiusY: 18; startAngle: -90; sweepAngle: Math.min(1.0, root._netUpBps / (5 * 1024 * 1024)) * 360 } }
                }
                Text { anchors.centerIn: parent; text: "NUP"; font.family: Theme.fontFamily; font.pixelSize: 9; font.letterSpacing: 1.6; color: root._mutedText }
                MouseArea { id: nupMA; anchors.fill: parent; hoverEnabled: true; onClicked: { root._hideHost(); nethogProc.running = true } }
            }

        }

        // ── Row 2: WI-FI · VPN · UPDATE ──────────────────────────────────────
        Item {
            id: netRow
            width: parent.width - 50
            height: 36
            anchors.horizontalCenter: parent.horizontalCenter

            Repeater {
                model: root._netTiles
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    property real tileW: (netRow.width - 20) / 3
                    x: index === 0 ? 20 : (tileW + 10)
                    y: 0
                    width: tileW
                    height: 36
                    radius: 16
                    color: "transparent"
                    border.width: 0

                    // single-line layout (e.g. VPN)
                    Item {
                        visible: modelData.singleLine || false
                        anchors.fill: parent
                        Row {
                            anchors.centerIn: parent
                            height: parent.height
                            spacing: 6
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.icon; font.family: "Symbols Nerd Font"
                                font.pixelSize: 14
                                color: tileMA.containsMouse ? root._accentColor : root._mutedText
                                Behavior on color { ColorAnimation { duration: 150 } }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.detail; font.family: Theme.fontFamily
                                font.pixelSize: 9; font.bold: true; color: root._textColor
                            }
                        }
                    }

                    // two-line layout (e.g. WI-FI)
                    Column {
                        visible: !(modelData.singleLine || false)
                        anchors { fill: parent; topMargin: 10; bottomMargin: 10; leftMargin: 14; rightMargin: 14 }
                        spacing: 4

                        Item {
                            width: parent.width; height: 14
                            Text {
                                anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - tileStatus.width - 4
                                text: modelData.label || ""; font.family: Theme.fontFamily
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
                            width: parent.width; text: modelData.detail || ""
                            font.family: Theme.fontFamily; font.pixelSize: 9
                            color: root._textColor; elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: tileMA
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: modelData.interactive
                        cursorShape: modelData.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: {
                            if (modelData.key === "wifi") root._toggleWifi()
                            else if (modelData.key === "vpn") root._toggleVpn()
                        }
                    }
                }
            }

            // ── UPDATE ───────────────────────────────────────────────────────
            Rectangle {
                id: updateTile
                x: 2 * ((netRow.width - 20) / 3 + 10) - 20
                y: 0
                width: (netRow.width - 20) / 3
                height: 36
                radius: 16
                color: "transparent"

                Item {
                    anchors.fill: parent
                    Row {
                        anchors.centerIn: parent
                        height: parent.height
                        spacing: 6
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: ""; font.family: "Symbols Nerd Font"
                            font.pixelSize: 14
                            color: circleMA.containsMouse ? root._accentColor : root._mutedText
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (root._fetching || root._updating) ? "…" : (root._packages.length === 0 ? "CLEAN" : ("PKGs " + root._packages.length))
                            font.family: Theme.fontFamily; font.pixelSize: 9; font.bold: true
                            color: root._textColor
                        }
                    }
                }
                MouseArea {
                    id: circleMA
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root._startUpdate()
                    onPressAndHold: root._fetchUpdates()
                }
            }
        }
    }
}
