import QtQuick 2.15
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    readonly property bool _isRainbow: Theme.isRainbow(moduleConfig, "textColor")
    readonly property real _rainbowAlpha: Theme.rainbowAlpha(moduleConfig, "textColor")
    readonly property string _handColorStr: Theme.value(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _handColor: _isRainbow
        ? Theme.positionalRainbowColor(moduleConfig, _rainbowAlpha)
        : Theme.parse(_handColorStr, "#F8F8F2FF")

    property int _h: 0
    property int _m: 0
    property int _s: 0

    function _tick() {
        const now = new Date()
        _h = now.getHours()
        _m = now.getMinutes()
        _s = now.getSeconds()
        handsCanvas.requestPaint()
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._tick()
    }

    Canvas {
        id: handsCanvas
        anchors.fill: parent

        function cs(color) {
            return "rgba(" + Math.round(color.r * 255) + "," +
                             Math.round(color.g * 255) + "," +
                             Math.round(color.b * 255) + "," +
                             color.a.toFixed(3) + ")"
        }

        function makeRainbowGradient(ctx) {
            const g = ctx.createLinearGradient(0, height, width, 0)
            g.addColorStop(0.00, "rgba(90,255,90,1)")
            g.addColorStop(0.16, "rgba(0,255,220,1)")
            g.addColorStop(0.32, "rgba(0,120,255,1)")
            g.addColorStop(0.48, "rgba(150,90,255,1)")
            g.addColorStop(0.64, "rgba(255,80,160,1)")
            g.addColorStop(0.80, "rgba(255,120,0,1)")
            g.addColorStop(1.00, "rgba(255,240,60,1)")
            return g
        }

        function drawHand(ctx, x1, y1, x2, y2, style, glowAlpha, coreW) {
            ctx.lineCap = "round"
            ctx.strokeStyle = style
            ctx.globalAlpha = glowAlpha * 0.5
            ctx.lineWidth = coreW + 8
            ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
            ctx.globalAlpha = glowAlpha
            ctx.lineWidth = coreW + 3
            ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
            ctx.globalAlpha = root._rainbowAlpha
            ctx.lineWidth = coreW
            ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(x2, y2); ctx.stroke()
            ctx.globalAlpha = 1.0
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.globalAlpha = 1.0

            const cx = width  / 2
            const cy = height / 2
            const R  = Math.min(width, height) / 2 - 2

            const style = root._isRainbow ? makeRainbowGradient(ctx) : cs(root._handColor)

            // Hour hand
            const hourAngle = -Math.PI / 2 +
                ((root._h % 12) / 12 + root._m / 720 + root._s / 43200) * Math.PI * 2
            drawHand(ctx,
                cx - Math.cos(hourAngle) * R * 0.14, cy - Math.sin(hourAngle) * R * 0.14,
                cx + Math.cos(hourAngle) * R * 0.52, cy + Math.sin(hourAngle) * R * 0.52,
                style, 0.18, 20)

            // Minute hand
            const minAngle = -Math.PI / 2 +
                (root._m / 60 + root._s / 3600) * Math.PI * 2
            drawHand(ctx,
                cx - Math.cos(minAngle) * R * 0.10, cy - Math.sin(minAngle) * R * 0.10,
                cx + Math.cos(minAngle) * R * 0.78, cy + Math.sin(minAngle) * R * 0.78,
                style, 0.14, 12)

            // Center cap
            ctx.globalAlpha = root._rainbowAlpha
            ctx.beginPath()
            ctx.arc(cx, cy, 18, 0, Math.PI * 2)
            ctx.fillStyle = style
            ctx.fill()
            ctx.globalAlpha = 1.0
        }
    }
}
