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
            "[general]\nbars = " + root._barCount + "\nframerate = 30\nautosens = 1\nsensitivity = 100\n\n" +
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
        command: ["cava", "-p", root._cavaCfgPath]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                const vals = data.trim().split(" ").map(Number)
                if (vals.length > 0 && !isNaN(vals[0])) {
                    root._cavaData = vals
                    const framePeak = Math.max.apply(Math, vals)
                    if (framePeak > root._displayPeak) {
                        root._displayPeak = framePeak
                    } else {
                        root._displayPeak = Math.max(24, root._displayPeak * 0.92 + framePeak * 0.08)
                    }
                    cavaCanvas.requestPaint()
                }
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

    Canvas {
        id: cavaCanvas
        anchors.fill: parent

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const data = root._cavaData
            const count = root._barCount
            if (!data || data.length === 0) return

            const barCell = width / count
            const gap = Math.max(1, barCell * 0.16)
            const barWidth = Math.max(1, barCell - gap)
            const maxH = Math.max(1, height)
            const ac = root._accentColor
            const dynamicPeak = Math.max(24, root._displayPeak)
            const scale = maxH / dynamicPeak

            for (let i = 0; i < count; i++) {
                const raw = data[i] || 0
                const barHeight = Math.min(maxH, Math.round(Math.max(2, raw * scale)))
                const x = i * barCell + gap / 2
                const y = height - barHeight
                const alpha = 0.08 + Math.min(1, raw / dynamicPeak) * 0.28

                ctx.fillStyle = Qt.rgba(ac.r, ac.g, ac.b, alpha)
                const radius = Math.min(4, barWidth / 2, barHeight / 2)
                ctx.beginPath()
                ctx.moveTo(x + radius, y)
                ctx.lineTo(x + barWidth - radius, y)
                ctx.arcTo(x + barWidth, y, x + barWidth, y + radius, radius)
                ctx.lineTo(x + barWidth, height)
                ctx.lineTo(x, height)
                ctx.lineTo(x, y + radius)
                ctx.arcTo(x, y, x + radius, y, radius)
                ctx.closePath()
                ctx.fill()
            }
        }
    }
}
