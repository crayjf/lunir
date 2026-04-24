import QtQuick 2.15
import Quickshell
import "../lib"

// Per-widget Item inside the desktop wallpaper surface.
// Positioned absolutely (x/y). Animation is handled by the container.
// Drag: host-defined left-button gesture. Resize: right-button drag.
Item {
    id: win

    property var moduleConfig: null
    property int moveModifiers: Qt.NoModifier
    property string gridControllerId: "desktop-grid-overlay"
    property string hostControllerId: ""

    function _applyLoaderProps() {
        const item = moduleLoader.item
        if (!item) return
        item.moduleConfig = win.moduleConfig
        if (item.hostControllerId !== undefined)
            item.hostControllerId = win.hostControllerId
    }

    readonly property int _minW: moduleConfig ? (moduleConfig.minWidth  ?? 150) : 150
    readonly property int _minH: moduleConfig ? (moduleConfig.minHeight ?? 40)  : 40
    readonly property bool _spanMonitorWidth: !!(moduleConfig && moduleConfig.spanMonitorWidth)
    readonly property bool _stickToBottom: !!(moduleConfig && moduleConfig.stickToBottom)
    readonly property real _maxHeightRatio: moduleConfig && moduleConfig.maxHeightRatio !== undefined
        ? Number(moduleConfig.maxHeightRatio)
        : 0
    property real _x: 0
    property real _y: 0
    property real _w: _minW
    property real _h: _minH

    property bool _dragging: false
    property bool _resizing: false

    x: _x;     y: _y
    width: _w; height: _h

    // ── Config sync ────────────────────────────────────────────────────────────
    function _maxAllowedHeight() {
        if (_maxHeightRatio > 0 && parent)
            return Math.max(_minH, parent.height * _maxHeightRatio)
        return Infinity
    }

    function _syncFromConfig() {
        if (!moduleConfig || _dragging || _resizing) return
        const maxH = _maxAllowedHeight()
        _w = _spanMonitorWidth && parent
            ? parent.width
            : (moduleConfig.width ?? _minW)
        _h = Math.min(moduleConfig.height ?? _minH, maxH)
        _x = _spanMonitorWidth ? 0 : (moduleConfig.x ?? 0)
        _y = _stickToBottom && parent
            ? Math.max(0, parent.height - _h)
            : (moduleConfig.y ?? 0)
    }

    onModuleConfigChanged: {
        _syncFromConfig()
        _applyLoaderProps()
    }
    onParentChanged: _syncFromConfig()
    on_StickToBottomChanged: _syncFromConfig()
    on_SpanMonitorWidthChanged: _syncFromConfig()
    on_MaxHeightRatioChanged: _syncFromConfig()

    Connections {
        target: win.parent
        function onWidthChanged() { win._syncFromConfig() }
        function onHeightChanged() { win._syncFromConfig() }
    }

    function snap(v) { return Math.round(v / 20) * 20 }

    function _showGrid() {
        if (win.gridControllerId) ModuleControllers.show(win.gridControllerId)
    }

    function _hideGrid() {
        if (win.gridControllerId) ModuleControllers.hide(win.gridControllerId)
    }

    // ── Visual chrome ──────────────────────────────────────────────────────────
    Rectangle {
        id: chrome
        anchors.fill: parent
        color: Theme.color(win.moduleConfig, "widgetBackground", "#282A36F0")
        radius: Theme.number(win.moduleConfig, "widgetBorderRadius", 12)
        border.color: Theme.color(win.moduleConfig, "widgetBorderColor", "#F8F8F21F")
        border.width: Theme.number(win.moduleConfig, "widgetBorderWidth", 1)
        clip: true

        RainbowBorder {
            anchors.fill: parent
            visible: Theme.isRainbowBorder(win.moduleConfig) && chrome.border.width > 0
            radius: chrome.radius
            lineWidth: chrome.border.width
            z: 10
        }

        Item {
            id: contentArea
            anchors { fill: parent; margins: 8 }

            Loader {
                id: moduleLoader
                anchors.fill: parent
                source: win.moduleConfig ? ModuleRegistry.url(win.moduleConfig.type) : ""
                onLoaded: win._applyLoaderProps()
            }
        }
    }

    onHostControllerIdChanged: _applyLoaderProps()

    // ── Ctrl + drag to move ────────────────────────────────────────────────────
    DragHandler {
        id: moveDrag
        target: null
        acceptedModifiers: win.moveModifiers
        acceptedButtons: Qt.LeftButton
        grabPermissions: PointerHandler.ApprovesTakeOverByAnything

        property real _sx: 0
        property real _sy: 0

        onActiveChanged: {
            if (active) {
                win._dragging = true
                _sx = win._x
                _sy = win._y
                win._showGrid()
            } else {
                win._dragging = false
                win._hideGrid()
            }
        }

        onCentroidChanged: {
            if (!active) return
            const dx = centroid.scenePosition.x - centroid.scenePressPosition.x
            const dy = centroid.scenePosition.y - centroid.scenePressPosition.y
            if (!win._spanMonitorWidth)
                win._x = snap(_sx + dx)
            if (!win._stickToBottom)
                win._y = snap(_sy + dy)
        }
    }

    // ── Right-drag resize ──────────────────────────────────────────────────────
    DragHandler {
        id: resizeDrag
        target: null
        acceptedModifiers: Qt.NoModifier
        acceptedButtons: Qt.RightButton
        grabPermissions: PointerHandler.CanTakeOverFromAnything

        property real _sw: 0
        property real _sh: 0

        onActiveChanged: {
            if (active) {
                win._resizing = true
                _sw = win._w
                _sh = win._h
                win._showGrid()
            } else {
                win._resizing = false
                win._hideGrid()
            }
        }

        onCentroidChanged: {
            if (!active) return
            const dx = centroid.scenePosition.x - centroid.scenePressPosition.x
            const dy = centroid.scenePosition.y - centroid.scenePressPosition.y
            const nextH = snap(Math.max(win._minH, _sh + dy))
            if (!win._spanMonitorWidth)
                win._w = snap(Math.max(win._minW, _sw + dx))
            win._h = Math.min(nextH, win._maxAllowedHeight())
            if (win._stickToBottom && win.parent)
                win._y = Math.max(0, win.parent.height - win._h)
        }
    }
}
