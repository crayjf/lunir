import QtQuick 2.15
import Quickshell
import Quickshell.Wayland
import "../lib"

PanelWindow {
    id: win

    WlrLayershell.layer: WlrLayershell.Bottom
    WlrLayershell.namespace: "desktop-widgets"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    visible: true

    readonly property bool _isPrimaryScreen: win.screen === Quickshell.screens[0]
    property var _desktopModules: win.screen === Quickshell.screens[0] ? ModuleRegistry.desktopModules : []
    property bool _desktopGridVisible: false

    Canvas {
        id: desktopGridCanvas
        anchors.fill: parent
        z: 1
        visible: win._desktopGridVisible
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

    Item {
        id: desktopWidgetContainer
        anchors.fill: parent
        z: 2

        Repeater {
            model: win._desktopModules
            WidgetItem {
                required property var modelData
                moduleConfig: modelData
                moveModifiers: Qt.NoModifier
            }
        }
    }

    Component.onCompleted: {
        if (!win._isPrimaryScreen)
            return
        ModuleControllers.register("desktop-grid-overlay", {
            "show": function() { win._desktopGridVisible = true },
            "hide": function() { win._desktopGridVisible = false },
            "toggle": function() { win._desktopGridVisible = !win._desktopGridVisible },
            "isVisible": function() { return win._desktopGridVisible }
        })
    }

    Component.onDestruction: {
        if (win._isPrimaryScreen)
            ModuleControllers.unregister("desktop-grid-overlay")
    }
}
