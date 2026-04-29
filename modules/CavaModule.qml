import QtQuick 2.15
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property var _cfg: moduleConfig ? (moduleConfig.props || {}) : ({})
    readonly property string _barShape: root._cfg.barShape || "clean"

    // Reactive: re-evaluates whenever Config.cava is reassigned (e.g. on file reload).
    // Per-widget color wins; global Config.cava.barColor is only a fallback.
    readonly property string _barColorStr: {
        if (root._cfg.barColor !== undefined && root._cfg.barColor !== null && root._cfg.barColor !== "")
            return root._cfg.barColor
        const live = Config.cava ? Config.cava.barColor : null
        if (live !== undefined && live !== null) return live
        return ""
    }
    readonly property bool _isRainbow: root._barColorStr.startsWith("#rainbow")

    readonly property var players: Mpris.players.values
    readonly property var player: {
        const players = root.players
        const active = players.find(function(player) { return player.isPlaying })
        return active || (players.length > 0 ? players[0] : null)
    }
    readonly property bool playing: player ? player.isPlaying : false
    readonly property int _barCount: Math.max(16, root._cfg.bars || 96)
    readonly property string _cavaCfgPath: Quickshell.statePath("cava-widget.ini")

    property var _cavaData: []
    property real _displayPeak: 64
    property real _rainbowPhase: 0

    // Bring back animated rainbow for cava only.
    Timer {
        id: rainbowTimer
        interval: 33
        repeat: true
        running: root._isRainbow && root.visible && !root.playing
        onTriggered: {
            root._rainbowPhase = (root._rainbowPhase + 0.7) % 360
            cavaCanvas.requestPaint()
        }
    }

    function _syncVisualizer() {
        if (!root.visible || !root.playing) {
            if (cavaProc.running) cavaProc.running = false
            return
        }

        if (!cavaProc.running && !writeCfgProc.running) writeCfgProc.running = true
    }

    Process {
        id: writeCfgProc
        command: ["sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"",
            "sh", root._cavaCfgPath,
            "[general]\nbars = " + root._barCount + "\nframerate = 60\nautosens = 1\nsensitivity = 100\n\n" +
            "[input]\nmethod = pulse\nsource = auto\n\n" +
            "[output]\nmethod = raw\nraw_target = /dev/stdout\n" +
            "data_format = ascii\nbar_delimiter = 32\nframe_delimiter = 10\nbit_format = 8\n"]
        running: false
        onExited: (code) => {
            if (code !== 0) {
                console.warn("Failed to write cava config:", root._cavaCfgPath)
                return
            }
            if (root.visible && root.playing && !cavaProc.running) cavaProc.running = true
        }
    }

    Process {
        id: cavaProc
        command: ["stdbuf", "-o0", "cava", "-p", root._cavaCfgPath]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                const parts = data.trim().split(" ")
                if (parts.length === 0 || isNaN(+parts[0])) return
                const vals = new Array(parts.length)
                let framePeak = 0
                for (let j = 0; j < parts.length; j++) {
                    const v = +parts[j]
                    vals[j] = v
                    if (v > framePeak) framePeak = v
                }
                root._cavaData = vals
                if (framePeak > root._displayPeak) {
                    root._displayPeak = framePeak
                } else {
                    root._displayPeak = Math.max(24, root._displayPeak * 0.92 + framePeak * 0.08)
                }
                if (root._isRainbow)
                    root._rainbowPhase = (root._rainbowPhase + 0.7) % 360
                cavaCanvas.requestPaint()
            }
        }
        onExited: {
            root._cavaData = []
            root._displayPeak = 64
            cavaCanvas.requestPaint()
        }
    }

    onPlayingChanged: root._syncVisualizer()
    onPlayerChanged: root._syncVisualizer()
    onVisibleChanged: root._syncVisualizer()
    on_BarCountChanged: root._syncVisualizer()

    FontLoader {
        id: hardstreetLoader
        source: "file:///home/crayjf/.local/share/fonts/HARDSTREET.ttf"
        onStatusChanged: { if (status === FontLoader.Ready) cavaCanvas.requestPaint() }
    }

    Canvas {
        id: cavaCanvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const data = root._cavaData
            const count = root._barCount
            if (!data || data.length === 0) return

            const isDistressed = root._barShape === "distressed"
            const barCell = width / count
            const gap = Math.max(1, barCell * (isDistressed ? 0.08 : 0.16))
            const bw = Math.max(1, barCell - gap)
            const maxH = Math.max(1, height)
            const dynamicPeak = Math.max(24, root._displayPeak)
            const scale = maxH / dynamicPeak

            const cfgHex = root._barColorStr
            const isRainbow = root._isRainbow
            const phase = root._rainbowPhase
            // #rainbowXY: last 2 chars are hex opacity
            const rainbowAlpha = (isRainbow && cfgHex.length === 10)
                ? parseInt(cfgHex.substring(8, 10), 16) / 255 : 1.0

            // Precompute fixed-color style string once (no per-bar allocation)
            let fixedStyle = ""
            if (!isRainbow && cfgHex.length === 9 && cfgHex[0] === '#') {
                fixedStyle = "rgba(" +
                    parseInt(cfgHex.substring(1, 3), 16) + "," +
                    parseInt(cfgHex.substring(3, 5), 16) + "," +
                    parseInt(cfgHex.substring(5, 7), 16) + "," +
                    (parseInt(cfgHex.substring(7, 9), 16) / 255).toFixed(3) + ")"
            }

            // Precompute accent RGB prefix to avoid per-bar QML property reads
            const ac = root._accentColor
            const acR = ac.r * 255 | 0
            const acG = ac.g * 255 | 0
            const acB = ac.b * 255 | 0

            // Fixed color: set once — no need to touch fillStyle inside the loop
            if (fixedStyle) ctx.fillStyle = fixedStyle

            for (let i = 0; i < count; i++) {
                const raw = data[i] || 0
                const t = Math.min(1, raw / dynamicPeak)
                const bh = Math.min(maxH, Math.max(2, (raw * scale + 0.5) | 0))
                const x = i * barCell + gap * 0.5
                const y = height - bh

                if (isRainbow) {
                    // Inline hue→RGB — no array allocation, no cross-object call
                    const h = (i / count * 360 + phase) % 360
                    const hp = h / 60
                    const hi = hp | 0
                    const c = 0.78, m = 0.22
                    const xv = c * (1 - Math.abs((hp % 2) - 1))
                    let r = m, g = m, b = m
                    if      (hi === 0) { r += c; g += xv }
                    else if (hi === 1) { r += xv; g += c }
                    else if (hi === 2) { g += c; b += xv }
                    else if (hi === 3) { g += xv; b += c }
                    else if (hi === 4) { r += xv; b += c }
                    else               { r += c; b += xv }
                    const a = (rainbowAlpha * (0.12 + t * 0.88)).toFixed(3)
                    ctx.fillStyle = "rgba(" + (r * 255 | 0) + "," + (g * 255 | 0) + "," + (b * 255 | 0) + "," + a + ")"
                } else if (!fixedStyle) {
                    ctx.fillStyle = "rgba(" + acR + "," + acG + "," + acB + "," + (0.08 + t * 0.28).toFixed(3) + ")"
                }

                if (!isDistressed) {
                    ctx.fillRect(x, y, bw, bh)
                } else {
                    ctx.font = (bh * 1.35 | 0) + "px 'HARD STREET'"
                    ctx.textBaseline = "alphabetic"
                    ctx.textAlign = "center"
                    ctx.fillText("I", x + bw * 0.5, y + bh)
                }
            }
        }
    }
}
