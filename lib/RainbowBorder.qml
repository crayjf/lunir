import QtQuick 2.15

Item {
    id: root

    property real radius: 0
    property real lineWidth: 1
    property real phase: 0

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        function _rgb(h) {
            const s = 1.0
            const l = 0.62
            const c = (1 - Math.abs(2 * l - 1)) * s
            const hp = ((h % 360) + 360) % 360 / 60
            const x = c * (1 - Math.abs((hp % 2) - 1))
            let r = 0, g = 0, b = 0
            if (hp < 1)      { r = c; g = x }
            else if (hp < 2) { r = x; g = c }
            else if (hp < 3) { g = c; b = x }
            else if (hp < 4) { g = x; b = c }
            else if (hp < 5) { r = x; b = c }
            else             { r = c; b = x }
            const m = l - c / 2
            return "rgba(" + Math.round((r + m) * 255) + "," +
                             Math.round((g + m) * 255) + "," +
                             Math.round((b + m) * 255) + ",1)"
        }

        function _point(distance, box) {
            const x = box.x, y = box.y, w = box.w, h = box.h, r = box.r
            const top = Math.max(0, w - 2 * r)
            const side = Math.max(0, h - 2 * r)
            const arc = Math.PI * r / 2
            const pieces = [
                top, arc, side, arc, top, arc, side, arc
            ]
            let d = distance
            for (let i = 0; i < pieces.length; i++) {
                if (d <= pieces[i]) {
                    const t = pieces[i] <= 0 ? 0 : d / pieces[i]
                    if (i === 0) return { x: x + r + top * t, y: y }
                    if (i === 1) {
                        const a = -Math.PI / 2 + t * Math.PI / 2
                        return { x: x + w - r + Math.cos(a) * r, y: y + r + Math.sin(a) * r }
                    }
                    if (i === 2) return { x: x + w, y: y + r + side * t }
                    if (i === 3) {
                        const a = t * Math.PI / 2
                        return { x: x + w - r + Math.cos(a) * r, y: y + h - r + Math.sin(a) * r }
                    }
                    if (i === 4) return { x: x + w - r - top * t, y: y + h }
                    if (i === 5) {
                        const a = Math.PI / 2 + t * Math.PI / 2
                        return { x: x + r + Math.cos(a) * r, y: y + h - r + Math.sin(a) * r }
                    }
                    if (i === 6) return { x: x, y: y + h - r - side * t }
                    const a = Math.PI + t * Math.PI / 2
                    return { x: x + r + Math.cos(a) * r, y: y + r + Math.sin(a) * r }
                }
                d -= pieces[i]
            }
            return { x: x + r, y: y }
        }

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            if (root.lineWidth <= 0 || width <= 0 || height <= 0) return

            const lw = Math.max(1, root.lineWidth)
            const box = {
                x: lw / 2,
                y: lw / 2,
                w: Math.max(0, width - lw),
                h: Math.max(0, height - lw),
                r: Math.max(0, Math.min(root.radius - lw / 2, (width - lw) / 2, (height - lw) / 2))
            }
            const top = Math.max(0, box.w - 2 * box.r)
            const side = Math.max(0, box.h - 2 * box.r)
            const total = 2 * top + 2 * side + 2 * Math.PI * box.r
            if (total <= 0) return

            const steps = Math.max(120, Math.ceil(total / 2))
            ctx.lineWidth = lw
            ctx.lineCap = "round"
            ctx.lineJoin = "round"

            for (let i = 0; i < steps; i++) {
                const a = i / steps
                const b = (i + 1) / steps
                const p0 = _point(total * a, box)
                const p1 = _point(total * b, box)
                ctx.strokeStyle = _rgb((a * 360) + root.phase)
                ctx.beginPath()
                ctx.moveTo(p0.x, p0.y)
                ctx.lineTo(p1.x, p1.y)
                ctx.stroke()
            }
        }
    }

    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()
    onRadiusChanged: canvas.requestPaint()
    onLineWidthChanged: canvas.requestPaint()
    onPhaseChanged: canvas.requestPaint()
}
