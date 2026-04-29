import QtQuick 2.15
import Quickshell
import Quickshell.Wayland
import "../lib"

// Always-visible background wallpaper window (BACKGROUND layer).
PanelWindow {
    id: win

    WlrLayershell.layer: WlrLayershell.Background
    WlrLayershell.namespace: "wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "black"

    visible: true

    Image {
        anchors.fill: parent
        source: Config.wallpaper.current ? expandPath(Config.wallpaper.current) : ""
        fillMode: fitMode(Config.wallpaper.fit)
        sourceSize.width: win.width
        sourceSize.height: win.height
        asynchronous: true
        cache: false
    }

    Canvas {
        id: desktopGridCanvas
        anchors.fill: parent
        z: 1
        visible: DesktopState.editMode && win.screen === Quickshell.screens[0]
        enabled: false

        onVisibleChanged: { if (visible) requestPaint() }
        onWidthChanged: requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const G = 20
            const cx = width / 2
            const cy = height / 2

            const r = Theme.text.r
            const g = Theme.text.g
            const b = Theme.text.b
            ctx.strokeStyle = "rgba(" + Math.round(r * 255) + "," + Math.round(g * 255) + "," + Math.round(b * 255) + ",0.07)"
            ctx.lineWidth = 0.5
            ctx.beginPath()
            for (let x = 0; x <= width; x += G) { ctx.moveTo(x, 0); ctx.lineTo(x, height) }
            for (let y = 0; y <= height; y += G) { ctx.moveTo(0, y); ctx.lineTo(width, y) }
            ctx.stroke()

            ctx.strokeStyle = "rgba(" + Math.round(r * 255) + "," + Math.round(g * 255) + "," + Math.round(b * 255) + ",0.28)"
            ctx.lineWidth = 1.5
            ctx.beginPath()
            ctx.moveTo(cx, 0); ctx.lineTo(cx, height)
            ctx.moveTo(0, cy); ctx.lineTo(width, cy)
            ctx.stroke()
        }
    }

    DesktopWidgetLayer {
        anchors.fill: parent
        z: 2
        screen: win.screen
        interactive: false
        visible: !DesktopState.editMode
    }

    function expandPath(p) { return p }

    function fitMode(fit) {
        switch (fit) {
            case "fill":       return Image.Stretch
            case "contain":    return Image.PreserveAspectFit
            case "scale-down": return Image.PreserveAspectFit
            default:           return Image.PreserveAspectCrop  // "cover"
        }
    }
}
