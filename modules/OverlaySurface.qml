import QtQuick 2.15
import Quickshell 0.1
import Quickshell.Wayland 0.1
import "../lib"

// Single fullscreen PanelWindow hosting all canvas widgets, keyboard handling,
// background tint, and drag/resize grid.
// Registered as "overlay" and "grid-overlay" with ModuleControllers.
PanelWindow {
    id: overlaySurface

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "lunir-qs"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    screen: Quickshell.screens.find(function(s) { return s.name === "DP-1" }) ?? Quickshell.screens[0]

    visible: false

    property real animScale: 0.0
    Behavior on animScale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    onAnimScaleChanged: { if (animScale <= 0.0) overlaySurface.visible = false }

    function show() {
        visible = true
        animScale = 1.0
    }

    function hide() {
        animScale = 0.0
        // visible = false handled by onAnimScaleChanged
        SelectedDay.reset()
    }

    // ── Background tint ────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        visible: Theme.overlayBackgroundEnabled
        opacity: overlaySurface.animScale
        color: Qt.rgba(Theme.overlayBackground.r, Theme.overlayBackground.g,
                       Theme.overlayBackground.b, Theme.overlayBackground.a)
    }

    // ── Keyboard ───────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: ModuleControllers.hide("overlay")

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
                _spawnNewNote()
                event.accepted = true
                return
            }
            ModuleControllers.keyForward(event.key, event.text, event.modifiers)
        }
    }

    // ── New note ───────────────────────────────────────────────────────────────
    function _spawnNewNote() {
        const W = 270, H = 220
        const id = "note-" + Date.now()
        Config.addModule({
            id: id,
            type: "note",
            enabled: true,
            mode: "canvas",
            x: Math.round((overlaySurface.width  - W) / 2),
            y: Math.round((overlaySurface.height - H) / 2),
            width: W,
            height: H,
            props: { title: "", body: "" }
        })
    }

    // ── Canvas modules ─────────────────────────────────────────────────────────
    property var _canvasModules: Config.modules.filter(
        function(m) { return m.enabled && m.mode === "canvas" })

    // Background click-to-close — fires on clicks outside any WidgetItem
    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: ModuleControllers.hide("overlay")
    }

    // ── Drag/resize grid ───────────────────────────────────────────────────────
    property bool _gridVisible: false

    Canvas {
        id: gridCanvas
        anchors.fill: parent
        z: 0
        visible: overlaySurface._gridVisible
        enabled: false

        onVisibleChanged: { if (visible) requestPaint() }
        onWidthChanged:  requestPaint()
        onHeightChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const G  = 20
            const cx = width  / 2
            const cy = height / 2

            const r = Theme.textColor.r, g = Theme.textColor.g, b = Theme.textColor.b
            ctx.strokeStyle = "rgba(" + Math.round(r*255) + "," + Math.round(g*255) + "," + Math.round(b*255) + ",0.07)"
            ctx.lineWidth = 0.5
            ctx.beginPath()
            for (let x = 0; x <= width;  x += G) { ctx.moveTo(x, 0);  ctx.lineTo(x, height) }
            for (let y = 0; y <= height; y += G) { ctx.moveTo(0, y);  ctx.lineTo(width, y)  }
            ctx.stroke()

            ctx.strokeStyle = "rgba(" + Math.round(r*255) + "," + Math.round(g*255) + "," + Math.round(b*255) + ",0.28)"
            ctx.lineWidth = 1.5
            ctx.beginPath()
            ctx.moveTo(cx, 0); ctx.lineTo(cx, height)
            ctx.moveTo(0, cy); ctx.lineTo(width, cy)
            ctx.stroke()
        }
    }

    // ── Widget container — scales all widgets from monitor center ──────────────
    Item {
        id: widgetContainer
        anchors.fill: parent
        z: 1
        transformOrigin: Item.Center
        scale: 0.88 + 0.12 * overlaySurface.animScale
        opacity: overlaySurface.animScale

        Repeater {
            model: overlaySurface._canvasModules
            WidgetItem {
                required property var modelData
                moduleConfig: modelData
            }
        }
    }

    // ── ModuleControllers registration ─────────────────────────────────────────
    Component.onCompleted: {
        ModuleControllers.register("overlay", {
            "show":      function() { overlaySurface.show() },
            "hide":      function() { overlaySurface.hide() },
            "toggle":    function() { if (overlaySurface.visible) overlaySurface.hide(); else overlaySurface.show() },
            "isVisible": function() { return overlaySurface.visible }
        })
        ModuleControllers.register("grid-overlay", {
            "show":      function() { overlaySurface._gridVisible = true  },
            "hide":      function() { overlaySurface._gridVisible = false },
            "toggle":    function() { overlaySurface._gridVisible = !overlaySurface._gridVisible },
            "isVisible": function() { return overlaySurface._gridVisible }
        })
    }

    Component.onDestruction: {
        ModuleControllers.unregister("overlay")
        ModuleControllers.unregister("grid-overlay")
    }
}
