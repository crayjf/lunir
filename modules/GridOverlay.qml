import QtQuick 2.15
import Quickshell 0.1
import Quickshell.Wayland 0.1
import "../lib"

// Fullscreen drag-grid surface — shown during WidgetWindow drag/resize operations.
// Registered as "grid-overlay" with ModuleControllers.
PanelWindow {
    id: win

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "lunir-qs"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    screen: Quickshell.screens.find(function(s) { return s.name === "DP-1" }) ?? Quickshell.screens[0]

    visible: false

    Canvas {
        id: grid
        anchors.fill: parent
        enabled: false

        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()

        Component.onCompleted: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const G  = 20
            const cx = width  / 2
            const cy = height / 2

            ctx.strokeStyle = "rgba(255,255,255,0.07)"
            ctx.lineWidth = 0.5
            ctx.beginPath()
            for (let x = 0; x <= width;  x += G) { ctx.moveTo(x, 0);      ctx.lineTo(x, height) }
            for (let y = 0; y <= height; y += G) { ctx.moveTo(0, y);      ctx.lineTo(width, y)  }
            ctx.stroke()

            ctx.strokeStyle = "rgba(255,255,255,0.28)"
            ctx.lineWidth = 1.5
            ctx.beginPath()
            ctx.moveTo(cx, 0); ctx.lineTo(cx, height)
            ctx.moveTo(0, cy); ctx.lineTo(width, cy)
            ctx.stroke()
        }
    }

    Component.onCompleted: {
        ModuleControllers.register("grid-overlay", {
            "show":      function() { win.visible = true  },
            "hide":      function() { win.visible = false },
            "toggle":    function() { win.visible = !win.visible },
            "isVisible": function() { return win.visible }
        })
    }

    Component.onDestruction: { ModuleControllers.unregister("grid-overlay") }
}
