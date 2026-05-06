import QtQuick 2.15
import Quickshell
import "../lib"
import "../lib/DesktopWidgetGeometry.js" as DesktopWidgetGeometry

// Per-widget Item inside the desktop wallpaper surface.
// Positioned absolutely (x/y). Animation is handled by the container.
// Drag: host-defined left-button gesture. Resize: right-button drag.
Item {
    id: win

    property var moduleConfig: null
    property int moveModifiers: Qt.NoModifier
    property string gridControllerId: "desktop-grid-overlay"
    property string hostControllerId: ""
    property bool interactive: true

    function _applyLoaderProps() {
        const item = moduleLoader.item
        if (!item) return
        item.moduleConfig = win.moduleConfig
        if (item.hostControllerId !== undefined)
            item.hostControllerId = win.hostControllerId
        if (item.autoSize === true)
            Qt.callLater(win._updateAutoWidth)
    }

    readonly property int _minW: moduleConfig ? (moduleConfig.minWidth  ?? 150) : 150
    readonly property int _minH: moduleConfig ? (moduleConfig.minHeight ?? 40)  : 40
    readonly property bool _spanMonitorWidth: !!(moduleConfig && moduleConfig.spanMonitorWidth)
    readonly property bool _stickToBottom: !!(moduleConfig && moduleConfig.stickToBottom)
    readonly property bool _autoSize: {
        if (moduleLoader.status !== Loader.Ready) return false
        const item = moduleLoader.item
        return item !== null && item.autoSize === true
    }
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
        return DesktopWidgetGeometry.maxAllowedHeight(_minH, _maxHeightRatio, parent ? parent.height : 0)
    }

    function _updateAutoWidth() {
        if (!_autoSize || _dragging || _resizing) return
        const item = moduleLoader.item
        if (!item || item.implicitWidth <= 0) return
        _w = item.implicitWidth
        _clampToParent()
    }

    function _syncFromConfig() {
        if (!moduleConfig || _dragging || _resizing) return
        const item = moduleLoader.item
        const geometry = DesktopWidgetGeometry.syncFromConfig(moduleConfig, {
            hostWidth: parent ? parent.width : 0,
            hostHeight: parent ? parent.height : 0,
            minWidth: _minW,
            minHeight: _minH,
            spanMonitorWidth: _spanMonitorWidth,
            stickToBottom: _stickToBottom,
            maxHeightRatio: _maxHeightRatio,
            autoSize: _autoSize,
            implicitWidth: item ? item.implicitWidth : 0
        })
        _x = geometry.x
        _y = geometry.y
        _w = geometry.width
        _h = geometry.height
    }

    function _clampToParent() {
        if (!parent) return
        const geometry = DesktopWidgetGeometry.clampGeometry({
            x: _x,
            y: _y,
            width: _w,
            height: _h
        }, {
            hostWidth: parent.width,
            hostHeight: parent.height,
            minWidth: _minW,
            minHeight: _minH,
            spanMonitorWidth: _spanMonitorWidth,
            stickToBottom: _stickToBottom,
            maxHeightRatio: _maxHeightRatio,
            autoSize: _autoSize
        })
        _x = geometry.x
        _y = geometry.y
        _w = geometry.width
        _h = geometry.height
    }

    function _persistGeometry() {
        if (!moduleConfig || !moduleConfig.id) return
        _clampToParent()
        Config.updateDesktopModule(moduleConfig.id, DesktopWidgetGeometry.persistedUpdates({
            x: _x,
            y: _y,
            width: _w,
            height: _h
        }, {
            spanMonitorWidth: _spanMonitorWidth,
            stickToBottom: _stickToBottom,
            autoSize: _autoSize
        }))
    }

    onModuleConfigChanged: {
        _syncFromConfig()
        _clampToParent()
        _applyLoaderProps()
    }
    onParentChanged: {
        _syncFromConfig()
        _clampToParent()
    }
    on_StickToBottomChanged: {
        _syncFromConfig()
        _clampToParent()
    }
    on_SpanMonitorWidthChanged: {
        _syncFromConfig()
        _clampToParent()
    }
    on_MaxHeightRatioChanged: {
        _syncFromConfig()
        _clampToParent()
    }

    Connections {
        target: moduleLoader.item
        enabled: win._autoSize
        function onImplicitWidthChanged() { win._updateAutoWidth() }
    }

    Connections {
        target: win.parent
        function onWidthChanged() {
            win._syncFromConfig()
            win._clampToParent()
        }
        function onHeightChanged() {
            win._syncFromConfig()
            win._clampToParent()
        }
    }

    function snap(v) { return DesktopWidgetGeometry.snap(v, 20) }

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
        radius: Theme.radiusSmall
        clip: true

        Item {
            id: contentArea
            anchors.fill: parent

            Loader {
                id: moduleLoader
                anchors.fill: parent
                source: win.moduleConfig ? ModuleRegistry.url(win.moduleConfig.type) : ""
                onLoaded: win._applyLoaderProps()
            }
        }
    }

    onHostControllerIdChanged: _applyLoaderProps()

    MouseArea {
        id: interactionArea
        anchors.fill: parent
        z: 100
        enabled: win.interactive
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        hoverEnabled: true
        preventStealing: true
        cursorShape: pressedButtons & Qt.RightButton ? Qt.SizeFDiagCursor
            : (pressedButtons & Qt.LeftButton ? Qt.SizeAllCursor : Qt.ArrowCursor)

        property real _pressParentX: 0
        property real _pressParentY: 0
        property real _startX: 0
        property real _startY: 0
        property real _startW: 0
        property real _startH: 0

        function _parentPoint(mouse) {
            if (!win.parent)
                return Qt.point(mouse.x, mouse.y)
            return interactionArea.mapToItem(win.parent, mouse.x, mouse.y)
        }

        function _finishInteraction() {
            const wasActive = win._dragging || win._resizing
            win._dragging = false
            win._resizing = false
            win._hideGrid()
            if (wasActive)
                win._persistGeometry()
        }

        onPressed: function(mouse) {
            const point = _parentPoint(mouse)
            _pressParentX = point.x
            _pressParentY = point.y
            _startX = win._x
            _startY = win._y
            _startW = win._w
            _startH = win._h

            win._dragging = mouse.button === Qt.LeftButton
            win._resizing = mouse.button === Qt.RightButton
            if (win._dragging || win._resizing)
                win._showGrid()
            mouse.accepted = true
        }

        onPositionChanged: function(mouse) {
            if (!win._dragging && !win._resizing)
                return

            const point = _parentPoint(mouse)
            const dx = point.x - _pressParentX
            const dy = point.y - _pressParentY

            if (win._dragging) {
                if (!win._spanMonitorWidth)
                    win._x = snap(_startX + dx)
                if (!win._stickToBottom)
                    win._y = snap(_startY + dy)
            } else if (win._resizing) {
                const nextH = snap(Math.max(win._minH, _startH + dy))
                if (!win._spanMonitorWidth)
                    win._w = snap(Math.max(win._minW, _startW + dx))
                win._h = Math.min(nextH, win._maxAllowedHeight())
                if (win._stickToBottom && win.parent)
                    win._y = Math.max(0, win.parent.height - win._h)
            }

            win._clampToParent()
            mouse.accepted = true
        }

        onReleased: function(mouse) {
            _finishInteraction()
            mouse.accepted = true
        }

        onCanceled: _finishInteraction()
    }
}
