import QtQuick 2.15
import Quickshell.Io 0.1
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    // ── State ─────────────────────────────────────────────────────────────────
    property string playerName: ""
    property string title:      "NO PLAYER"
    property string artist:     "—"
    property string timeText:   ""
    property string artPath:    ""
    property real   progress:   0.0
    property bool   playing:    false

    property var  _cavaData:    []
    property string _lastArtUrl: ""
    readonly property int _BARS: 28
    readonly property string _CAVA_CFG: "/tmp/lunir-cava.ini"
    readonly property string _ART_CACHE: "/tmp/lunir-media-art"

    // ── Write cava config ─────────────────────────────────────────────────────
    Process {
        id: writeCfgProc
        command: ["sh", "-c", "printf '%s' \"$1\" > /tmp/lunir-cava.ini", "sh",
            "[general]\nbars = 28\nframerate = 30\nautosens = 0\nsensitivity = 100\n\n" +
            "[input]\nmethod = pulse\nsource = auto\n\n" +
            "[output]\nmethod = raw\nraw_target = /dev/stdout\n" +
            "data_format = ascii\nbar_delimiter = 32\nframe_delimiter = 10\nbit_format = 8\n"]
        running: false
    }

    // ── Cava process (continuous stdout) ──────────────────────────────────────
    Process {
        id: cavaProc
        command: ["cava", "-p", root._CAVA_CFG]
        running: false
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: function(data) {
                const vals = data.trim().split(" ").map(Number)
                if (vals.length > 0 && !isNaN(vals[0])) {
                    root._cavaData = vals
                    cavaCanvas.requestPaint()
                }
            }
        }
        onExited: {
            root._cavaData = []
            cavaCanvas.requestPaint()
        }
    }

    // ── playerctl poll ────────────────────────────────────────────────────────
    Process {
        id: pollProc
        command: ["playerctl", "metadata", "--format",
            "{{playerName}}\t{{xesam:title}}\t{{xesam:artist}}\t{{mpris:length}}\t{{status}}\t{{position}}\t{{mpris:artUrl}}"]
        running: false
        stdout: StdioCollector { id: pollStdio }
        onExited: root._applyMeta(pollStdio.text.trim())
    }

    // ── Control processes ─────────────────────────────────────────────────────
    Process { id: prevProc;  command: ["playerctl","previous"];   running: false }
    Process { id: stopProc;  command: ["playerctl","stop"];       running: false }
    Process { id: playProc;  command: ["playerctl","play-pause"]; running: false }
    Process { id: nextProc;  command: ["playerctl","next"];       running: false }

    // ── Art download ──────────────────────────────────────────────────────────
    Process {
        id: artProc
        property string url: ""
        command: ["curl", "-s", "--max-time", "5", "-o", root._ART_CACHE, artProc.url]
        running: false
        onExited: root.artPath = "file://" + root._ART_CACHE
    }

    // ── Metadata parser ───────────────────────────────────────────────────────
    function _fmtTime(us) {
        const s = Math.floor(us / 1000000)
        const m = Math.floor(s / 60)
        return m + ":" + String(s % 60).padStart(2,"0")
    }

    function _applyMeta(meta) {
        if (!meta || meta.startsWith("\t") || meta.includes("No players found")) {
            root.title = "NO PLAYER"; root.artist = "—"; root.playerName = ""
            root.timeText = ""; root.progress = 0; root.playing = false
            if (cavaProc.running) cavaProc.running = false
            return
        }
        const p = meta.split("\t")
        root.playerName = p[0] || ""
        root.title      = p[1] || "—"
        root.artist     = p[2] || "—"
        const lenUs     = parseInt(p[3]||"0") || 0
        const status    = (p[4]||"").toLowerCase()
        const posUs     = parseInt(p[5]||"0") || 0
        const artUrl    = p[6] || ""

        root.playing = (status === "playing")
        if (root.playing) {
            if (!cavaProc.running) { writeCfgProc.running = true; cavaProc.running = true }
        } else {
            if (cavaProc.running) cavaProc.running = false
        }

        if (lenUs > 0) {
            root.progress = Math.min(posUs / lenUs, 1.0)
            root.timeText = _fmtTime(posUs) + " / " + _fmtTime(lenUs)
        } else {
            root.progress = 0; root.timeText = ""
        }

        if (artUrl && artUrl !== root._lastArtUrl) {
            root._lastArtUrl = artUrl
            if (artUrl.startsWith("file://")) {
                root.artPath = artUrl
            } else if (artUrl) {
                artProc.url = artUrl
                artProc.running = true
            }
        } else if (!artUrl && root._lastArtUrl) {
            root._lastArtUrl = ""; root.artPath = ""
        }
    }

    Timer {
        interval: 1000; repeat: true
        running: root.visible; triggeredOnStart: true
        onTriggered: pollProc.running = true
    }

    onVisibleChanged: {
        if (!visible && cavaProc.running) cavaProc.running = false
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors { fill: parent; margins: 10 }
        spacing: 8

        // Top row: art + info
        Row {
            width: parent.width
            spacing: 12

            // Album art
            Rectangle {
                width: 72; height: 72
                radius: 4
                color: Qt.rgba(1,1,1,0.08)
                clip: true
                Image {
                    anchors.fill: parent
                    source: root.artPath
                    fillMode: Image.PreserveAspectCrop
                    visible: root.artPath !== ""
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.artPath === ""
                    text: "♫"; font.pixelSize: 28
                    color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.3)
                }
            }

            // Info column
            Column {
                width: parent.width - 84
                height: 72
                spacing: 3
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    width: parent.width
                    Text {
                        text: root.title; width: parent.width - playerLabel.width
                        font.pixelSize: 12; color: Theme.textColor
                        elide: Text.ElideRight
                    }
                    Text {
                        id: playerLabel
                        text: root.playerName.toUpperCase()
                        font.pixelSize: 9
                        color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.5)
                    }
                }
                Row {
                    width: parent.width
                    Text {
                        text: root.artist; width: parent.width - timeLabel.width
                        font.pixelSize: 10
                        color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.7)
                        elide: Text.ElideRight
                    }
                    Text {
                        id: timeLabel
                        text: root.timeText; font.pixelSize: 9
                        color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.5)
                    }
                }
                // Progress bar
                Rectangle {
                    width: parent.width; height: 4; radius: 2
                    color: Qt.rgba(1,1,1,0.10)
                    Rectangle {
                        width: parent.width * root.progress; height: parent.height; radius: parent.radius
                        color: Theme.accentColor
                        Behavior on width { NumberAnimation { duration: 300 } }
                    }
                }
            }
        }

        // Controls
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4
            Repeater {
                model: [
                    {label:"⏮", proc: prevProc},
                    {label:"⏹", proc: stopProc},
                    {label: root.playing ? "⏸" : "▶", proc: playProc},
                    {label:"⏭", proc: nextProc},
                ]
                delegate: Rectangle {
                    width: 34; height: 28; radius: 3
                    color: ma.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
                    Text {
                        anchors.centerIn: parent
                        text: modelData.label; font.pixelSize: 14
                    }
                    MouseArea {
                        id: ma; anchors.fill: parent; hoverEnabled: true
                        onClicked: modelData.proc.running = true
                    }
                }
            }
        }

        // Cava canvas
        Canvas {
            id: cavaCanvas
            width: parent.width; height: 64

            onPaint: {
                const ctx  = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const data  = root._cavaData
                const count = root._BARS
                if (!data || data.length === 0) {
                    ctx.fillStyle = Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.15)
                    ctx.font = "20px sans-serif"
                    ctx.textAlign = "center"
                    ctx.fillText("♫", width/2, height/2 + 7)
                    return
                }
                const bW  = width / count
                const gap = Math.max(1, bW * 0.18)
                const bWidth = bW - gap
                const maxH = height * 0.86
                const ac = Theme.accentColor
                for (let i = 0; i < count; i++) {
                    const val = (data[i] || 0) / 255
                    const bh  = Math.round(val * maxH)
                    if (bh < 2 || bWidth < 1) continue
                    const x = i * bW + gap / 2
                    const y = height - bh
                    const alpha = 0.35 + val * 0.55
                    ctx.fillStyle = Qt.rgba(ac.r, ac.g, ac.b, alpha)
                    const r = Math.min(3, bWidth/2, bh/2)
                    ctx.beginPath()
                    ctx.moveTo(x+r, y)
                    ctx.lineTo(x+bWidth-r, y)
                    ctx.arcTo(x+bWidth, y, x+bWidth, y+r, r)
                    ctx.lineTo(x+bWidth, height)
                    ctx.lineTo(x, height)
                    ctx.lineTo(x, y+r)
                    ctx.arcTo(x, y, x+r, y, r)
                    ctx.closePath()
                    ctx.fill()
                }
            }
        }
    }
}
