import QtQuick 2.15
import Quickshell 0.1
import Quickshell.Wayland 0.1
import "../lib"

// Per-widget PanelWindow — each canvas module gets its own Wayland surface.
// Position is stored in margins (top/left) so the compositor can blur per-surface.
// Drag: Ctrl + left-button. Resize: left-button on any corner handle.
PanelWindow {
    id: win

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "lunir-qs"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; left: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    screen: Quickshell.screens.find(function(s) { return s.name === "DP-1" }) ?? Quickshell.screens[0]

    property var moduleConfig: null

    readonly property int _minW: moduleConfig ? (moduleConfig.minWidth  ?? 150) : 150
    readonly property int _minH: moduleConfig ? (moduleConfig.minHeight ?? 40)  : 40
    readonly property int _corner: 20

    // Internal position/size — driven from config, then mutated by drag/resize.
    property real _x: 0
    property real _y: 0
    property real _w: _minW
    property real _h: _minH

    // Guards so drag/resize don't get clobbered by config bindings mid-gesture.
    property bool _dragging:  false
    property bool _resizing:  false

    implicitWidth:  _w
    implicitHeight: _h

    margins {
        top:  _y
        left: _x
    }

    // Fade in/out
    visible: false

    property real fadeOpacity: 0.0
    Behavior on fadeOpacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    onFadeOpacityChanged: { if (fadeOpacity <= 0.0) win.visible = false }

    function show() { visible = true; fadeOpacity = 1.0 }
    function hide() { fadeOpacity = 0.0 }

    // Sync position/size from config whenever it changes (but not during gesture).
    function _syncFromConfig() {
        if (!moduleConfig || _dragging || _resizing) return
        _x = moduleConfig.x      ?? 0
        _y = moduleConfig.y      ?? 0
        _w = moduleConfig.width  ?? _minW
        _h = moduleConfig.height ?? _minH
    }

    onModuleConfigChanged: _syncFromConfig()

    function snap(v) { return Math.round(v / 20) * 20 }

    // ── Visual chrome ──────────────────────────────────────────────────────────
    Rectangle {
        id: chrome
        anchors.fill: parent
        color: Qt.rgba(Theme.widgetBackground.r, Theme.widgetBackground.g, Theme.widgetBackground.b,
                       Theme.widgetBackground.a * Theme.widgetOpacity * win.fadeOpacity)
        radius: Theme.widgetBorderRadius
        border.color: Theme.widgetBorderColor
        border.width: Theme.widgetBorderWidth
        clip: true

        Item {
            id: contentArea
            anchors { fill: parent; margins: 8 }

            Loader {
                id: moduleLoader
                anchors.fill: parent
                source: win.moduleConfig ? moduleUrl(win.moduleConfig.type) : ""

                onLoaded: {
                    if (item) item.moduleConfig = win.moduleConfig
                }
            }

            Binding {
                target: moduleLoader.item
                property: "moduleConfig"
                value: win.moduleConfig
                when: moduleLoader.status === Loader.Ready && moduleLoader.item !== null
            }
        }
    }

    // ── Ctrl + drag to move ────────────────────────────────────────────────────
    DragHandler {
        id: moveDrag
        target: null
        acceptedModifiers: Qt.ControlModifier
        acceptedButtons: Qt.LeftButton

        property real _sx: 0
        property real _sy: 0

        onActiveChanged: {
            if (active) {
                win._dragging = true
                _sx = win._x
                _sy = win._y
                ModuleControllers.show("grid-overlay")
            } else {
                win._dragging = false
                ModuleControllers.hide("grid-overlay")
                if (win.moduleConfig)
                    Config.updateModule(win.moduleConfig.id, { x: win._x, y: win._y })
            }
        }

        onCentroidChanged: {
            if (!active) return
            const dx = centroid.scenePosition.x - centroid.scenePressPosition.x
            const dy = centroid.scenePosition.y - centroid.scenePressPosition.y
            win._x = snap(_sx + dx)
            win._y = snap(_sy + dy)
        }
    }

    // ── Corner resize handles ──────────────────────────────────────────────────

    // Bottom-Right
    Item {
        x: win._w - win._corner; y: win._h - win._corner
        width: win._corner; height: win._corner
        z: 2
        HoverHandler { cursorShape: Qt.SizeFDiagCursor }
        DragHandler {
            target: null; acceptedModifiers: Qt.NoModifier; acceptedButtons: Qt.LeftButton
            property real _sw: 0; property real _sh: 0
            onActiveChanged: {
                if (active) { win._resizing = true; _sw = win._w; _sh = win._h; ModuleControllers.show("grid-overlay") }
                else {
                    win._resizing = false
                    ModuleControllers.hide("grid-overlay")
                    if (win.moduleConfig) Config.updateModule(win.moduleConfig.id,
                        { x: win._x, y: win._y, width: win._w, height: win._h })
                }
            }
            onCentroidChanged: {
                if (!active) return
                const dx = centroid.scenePosition.x - centroid.scenePressPosition.x
                const dy = centroid.scenePosition.y - centroid.scenePressPosition.y
                win._w = snap(Math.max(win._minW, _sw + dx))
                win._h = snap(Math.max(win._minH, _sh + dy))
            }
        }
    }

    // Bottom-Left
    Item {
        x: 0; y: win._h - win._corner
        width: win._corner; height: win._corner
        z: 2
        HoverHandler { cursorShape: Qt.SizeBDiagCursor }
        DragHandler {
            target: null; acceptedModifiers: Qt.NoModifier; acceptedButtons: Qt.LeftButton
            property real _sx: 0; property real _sw: 0; property real _sh: 0
            onActiveChanged: {
                if (active) { win._resizing = true; _sx = win._x; _sw = win._w; _sh = win._h; ModuleControllers.show("grid-overlay") }
                else {
                    win._resizing = false
                    ModuleControllers.hide("grid-overlay")
                    if (win.moduleConfig) Config.updateModule(win.moduleConfig.id,
                        { x: win._x, y: win._y, width: win._w, height: win._h })
                }
            }
            onCentroidChanged: {
                if (!active) return
                const dx = centroid.scenePosition.x - centroid.scenePressPosition.x
                const dy = centroid.scenePosition.y - centroid.scenePressPosition.y
                const nw = snap(Math.max(win._minW, _sw - dx))
                win._x = _sx + (_sw - nw)
                win._w = nw
                win._h = snap(Math.max(win._minH, _sh + dy))
            }
        }
    }

    // Top-Right
    Item {
        x: win._w - win._corner; y: 0
        width: win._corner; height: win._corner
        z: 2
        HoverHandler { cursorShape: Qt.SizeBDiagCursor }
        DragHandler {
            target: null; acceptedModifiers: Qt.NoModifier; acceptedButtons: Qt.LeftButton
            property real _sy: 0; property real _sw: 0; property real _sh: 0
            onActiveChanged: {
                if (active) { win._resizing = true; _sy = win._y; _sw = win._w; _sh = win._h; ModuleControllers.show("grid-overlay") }
                else {
                    win._resizing = false
                    ModuleControllers.hide("grid-overlay")
                    if (win.moduleConfig) Config.updateModule(win.moduleConfig.id,
                        { x: win._x, y: win._y, width: win._w, height: win._h })
                }
            }
            onCentroidChanged: {
                if (!active) return
                const dx = centroid.scenePosition.x - centroid.scenePressPosition.x
                const dy = centroid.scenePosition.y - centroid.scenePressPosition.y
                const nh = snap(Math.max(win._minH, _sh - dy))
                win._y = _sy + (_sh - nh)
                win._w = snap(Math.max(win._minW, _sw + dx))
                win._h = nh
            }
        }
    }

    // Top-Left
    Item {
        x: 0; y: 0
        width: win._corner; height: win._corner
        z: 2
        HoverHandler { cursorShape: Qt.SizeFDiagCursor }
        DragHandler {
            target: null; acceptedModifiers: Qt.NoModifier; acceptedButtons: Qt.LeftButton
            property real _sx: 0; property real _sy: 0; property real _sw: 0; property real _sh: 0
            onActiveChanged: {
                if (active) { win._resizing = true; _sx = win._x; _sy = win._y; _sw = win._w; _sh = win._h; ModuleControllers.show("grid-overlay") }
                else {
                    win._resizing = false
                    ModuleControllers.hide("grid-overlay")
                    if (win.moduleConfig) Config.updateModule(win.moduleConfig.id,
                        { x: win._x, y: win._y, width: win._w, height: win._h })
                }
            }
            onCentroidChanged: {
                if (!active) return
                const dx = centroid.scenePosition.x - centroid.scenePressPosition.x
                const dy = centroid.scenePosition.y - centroid.scenePressPosition.y
                const nw = snap(Math.max(win._minW, _sw - dx))
                const nh = snap(Math.max(win._minH, _sh - dy))
                win._x = _sx + (_sw - nw)
                win._y = _sy + (_sh - nh)
                win._w = nw
                win._h = nh
            }
        }
    }

    // ── Module type → QML file ─────────────────────────────────────────────────
    function moduleUrl(type) {
        const map = {
            "clock":         "ClockModule.qml",
            "calendar":      "CalendarModule.qml",
            "today":         "TodayModule.qml",
            "tomorrow":      "TomorrowModule.qml",
            "weather":       "WeatherModule.qml",
            "perf":          "PerfModule.qml",
            "media":         "MediaModule.qml",
            "notifications": "NotificationsModule.qml",
            "audio":         "AudioModule.qml",
            "updates":       "UpdatesModule.qml",
            "note":          "NoteModule.qml",
            "launcher":      "LauncherModule.qml",
            "network":       "NetworkModule.qml",
            "wallpaper":     "WallpaperModule.qml",
            "quote":         "QuoteModule.qml",
            "garmin":        "GarminModule.qml",
            "empty":         "EmptyModule.qml",
        }
        return map[type] || "EmptyModule.qml"
    }
}
