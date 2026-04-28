import QtQuick 2.15
import QtQuick.Controls 2.15
import Quickshell.Io
import Quickshell.Widgets
import "../lib"

Item {
    id: root
    focus: visible

    property var moduleConfig: null

    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")

    readonly property string _wallpaperFolder: Config.wallpaper.folder || "~/Pictures/Wallpaper"
    readonly property string _currentWallpaper: Config.wallpaper.current || ""
    readonly property string _previewPath: (_selectedIdx >= 0 && _selectedIdx < _files.length) ? _files[_selectedIdx] : ""
    readonly property bool _hasSelection: _previewPath !== ""
    readonly property bool _hasMultiple: _files.length > 1
    readonly property string _previousPath: _hasMultiple && _selectedIdx >= 0
        ? _files[(_selectedIdx - 1 + _files.length) % _files.length] : ""
    readonly property string _nextPath: _hasMultiple && _selectedIdx >= 0
        ? _files[(_selectedIdx + 1) % _files.length] : ""
    readonly property bool _isAnimating: slideAnim.running
    property var _files: []
    property int _selectedIdx: -1
    property int _animStartIdx: -1
    property int _animDir: 0
    property real _slideProgress: 0.0

    function _wrapIndex(idx) {
        if (_files.length <= 0) return -1
        return (idx % _files.length + _files.length) % _files.length
    }
    function _pathAt(baseIdx, offset) {
        const wrapped = _wrapIndex(baseIdx + offset)
        return wrapped >= 0 ? _files[wrapped] : ""
    }
    function _shuffle(items) {
        const shuffled = (items || []).slice()
        for (let i = shuffled.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1))
            const tmp = shuffled[i]
            shuffled[i] = shuffled[j]
            shuffled[j] = tmp
        }
        return shuffled
    }

    function _syncSelection(preferredPath) {
        if (_files.length === 0) {
            _selectedIdx = -1
            return
        }

        const preferred = preferredPath || _currentWallpaper
        const idx = preferred ? _files.indexOf(preferred) : -1
        _selectedIdx = idx >= 0 ? idx : Math.max(0, Math.min(_selectedIdx, _files.length - 1))
    }

    function _refreshWallpapers() {
        scanProc.folder = _wallpaperFolder
        scanProc.running = true
    }

    function _selectIdx(idx) {
        if (_files.length === 0) return
        _selectedIdx = Math.max(0, Math.min(idx, _files.length - 1))
    }

    function _selectRelative(step) {
        if (_files.length === 0) return
        if (_isAnimating) return
        if (_selectedIdx < 0) {
            _selectIdx(0)
            return
        }

        _animStartIdx = _selectedIdx
        _animDir = step < 0 ? -1 : 1
        _slideProgress = 0
        slideAnim.start()
    }

    function _applySelected() {
        if (_hasSelection)
            Config.updateWallpaper({ current: _previewPath })
    }

    Process {
        id: scanProc
        property string folder: ""
        command: ["sh", "-c",
            "f=${1/#~/$HOME}; find \"$f\" -maxdepth 2 -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' " +
            "-o -iname '*.avif' -o -iname '*.tiff' \\) 2>/dev/null | sort",
            "sh", scanProc.folder]
        running: false
        stdout: StdioCollector { id: scanStdio }
        onExited: {
            const previousPath = root._previewPath
            const scanned = scanStdio.text.trim().split("\n").filter(function(line) { return line.trim().length > 0 })
            root._files = root._shuffle(scanned)
            root._syncSelection(previousPath)
        }
    }

    onVisibleChanged: {
        if (visible) {
            _refreshWallpapers()
            forceActiveFocus()
        }
    }

    Connections {
        target: Config
        function onWallpaperChanged() {
            if (!scanProc.running)
                root._syncSelection(root._currentWallpaper)
        }
    }

    Component.onCompleted: _refreshWallpapers()

    Keys.onLeftPressed: root._selectRelative(-1)
    Keys.onRightPressed: root._selectRelative(1)
    Keys.onReturnPressed: root._applySelected()
    Keys.onEnterPressed: root._applySelected()

    SequentialAnimation {
        id: slideAnim
        NumberAnimation {
            target: root
            property: "_slideProgress"
            from: 0
            to: 1
            duration: 220
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: {
                if (root._animDir !== 0 && root._animStartIdx >= 0)
                    root._selectedIdx = root._wrapIndex(root._animStartIdx + root._animDir)
                root._slideProgress = 0
                root._animStartIdx = -1
                root._animDir = 0
            }
        }
    }

    Item {
        id: heroArea
        anchors.fill: parent
        readonly property real _previewScale: 0.85
        readonly property real _centerGap: 12
        readonly property real _previewRadius: 18

        function _lerp(a, b, t) { return a + (b - a) * t }
        function _slotRect(name) {
            switch (name) {
            case "left":
                return { x: leftPreviewWrap.x, y: leftPreviewWrap.y, w: leftPreviewWrap.width, h: leftPreviewWrap.height }
            case "center":
                return { x: mainPreview.x, y: mainPreview.y, w: mainPreview.width, h: mainPreview.height }
            case "right":
                return { x: rightPreviewWrap.x, y: rightPreviewWrap.y, w: rightPreviewWrap.width, h: rightPreviewWrap.height }
            case "offLeft":
                return {
                    x: leftPreviewWrap.x - leftPreviewWrap.width - heroArea._centerGap,
                    y: leftPreviewWrap.y,
                    w: leftPreviewWrap.width,
                    h: leftPreviewWrap.height
                }
            case "offRight":
                return {
                    x: rightPreviewWrap.x + rightPreviewWrap.width + heroArea._centerGap,
                    y: rightPreviewWrap.y,
                    w: rightPreviewWrap.width,
                    h: rightPreviewWrap.height
                }
            default:
                return { x: 0, y: previewFrame.y, w: 0, h: previewFrame.height }
            }
        }
        function _mixRect(fromRect, toRect) {
            return {
                x: _lerp(fromRect.x, toRect.x, root._slideProgress),
                y: _lerp(fromRect.y, toRect.y, root._slideProgress),
                w: _lerp(fromRect.w, toRect.w, root._slideProgress),
                h: _lerp(fromRect.h, toRect.h, root._slideProgress)
            }
        }
        function _animatedRect(role) {
            if (root._animDir > 0) {
                if (role === "prev") return _mixRect(_slotRect("left"), _slotRect("offLeft"))
                if (role === "current") return _mixRect(_slotRect("center"), _slotRect("left"))
                if (role === "next") return _mixRect(_slotRect("right"), _slotRect("center"))
                if (role === "incoming") return _mixRect(_slotRect("offRight"), _slotRect("right"))
            } else if (root._animDir < 0) {
                if (role === "next") return _mixRect(_slotRect("right"), _slotRect("offRight"))
                if (role === "current") return _mixRect(_slotRect("center"), _slotRect("right"))
                if (role === "prev") return _mixRect(_slotRect("left"), _slotRect("center"))
                if (role === "incoming") return _mixRect(_slotRect("offLeft"), _slotRect("left"))
            }
            return _slotRect("center")
        }
        function _animatedPath(role) {
            if (root._animStartIdx < 0) return ""
            if (root._animDir > 0) {
                if (role === "prev") return root._pathAt(root._animStartIdx, -1)
                if (role === "current") return root._pathAt(root._animStartIdx, 0)
                if (role === "next") return root._pathAt(root._animStartIdx, 1)
                if (role === "incoming") return root._pathAt(root._animStartIdx, 2)
            } else if (root._animDir < 0) {
                if (role === "prev") return root._pathAt(root._animStartIdx, -1)
                if (role === "current") return root._pathAt(root._animStartIdx, 0)
                if (role === "next") return root._pathAt(root._animStartIdx, 1)
                if (role === "incoming") return root._pathAt(root._animStartIdx, -2)
            }
            return ""
        }

        Item {
            id: wallpaperContent
            anchors.fill: parent

            Item {
                id: previewFrame
                anchors.centerIn: parent
                width: parent.width * heroArea._previewScale
                height: parent.height * heroArea._previewScale
            }

            Item {
                id: leftPreviewWrap
                anchors.left: parent.left
                anchors.right: mainPreview.left
                anchors.top: previewFrame.top
                anchors.bottom: previewFrame.bottom
                anchors.rightMargin: heroArea._centerGap
                opacity: root._hasMultiple ? 1.0 : 0.0
                visible: !root._isAnimating

                ClippingRectangle {
                    id: leftPreview
                    anchors.fill: parent
                    radius: heroArea._previewRadius
                    color: Theme.accent

                    Image {
                        anchors.fill: parent
                        source: root._previousPath ? "file://" + root._previousPath : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: root._previousPath !== ""
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: root._previousPath === ""
                        color: Theme.accent
                    }
                }

                MouseArea {
                    anchors.fill: leftPreview
                    hoverEnabled: true
                    enabled: root._hasMultiple
                    onClicked: {
                        root.forceActiveFocus()
                        root._selectRelative(-1)
                    }
                    onWheel: (event) => {
                        root._selectRelative(event.angleDelta.y < 0 ? 1 : -1)
                        event.accepted = true
                    }
                }
            }

            Item {
                id: rightPreviewWrap
                anchors.left: mainPreview.right
                anchors.right: parent.right
                anchors.top: previewFrame.top
                anchors.bottom: previewFrame.bottom
                anchors.leftMargin: heroArea._centerGap
                opacity: root._hasMultiple ? 1.0 : 0.0
                visible: !root._isAnimating

                ClippingRectangle {
                    id: rightPreview
                    anchors.fill: parent
                    radius: heroArea._previewRadius
                    color: Theme.accent

                    Image {
                        anchors.fill: parent
                        source: root._nextPath ? "file://" + root._nextPath : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: root._nextPath !== ""
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: root._nextPath === ""
                        color: Theme.accent
                    }
                }

                MouseArea {
                    anchors.fill: rightPreview
                    hoverEnabled: true
                    enabled: root._hasMultiple
                    onClicked: {
                        root.forceActiveFocus()
                        root._selectRelative(1)
                    }
                    onWheel: (event) => {
                        root._selectRelative(event.angleDelta.y < 0 ? 1 : -1)
                        event.accepted = true
                    }
                }
            }

            ClippingRectangle {
                id: mainPreview
                anchors.horizontalCenter: previewFrame.horizontalCenter
                anchors.top: previewFrame.top
                anchors.bottom: previewFrame.bottom
                width: Math.min(previewFrame.width, Math.round(height * 16 / 9))
                radius: heroArea._previewRadius
                color: Theme.surface
                visible: !root._isAnimating

                Image {
                    anchors.fill: parent
                    source: root._hasSelection ? "file://" + root._previewPath : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: root._hasSelection
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !root._hasSelection
                    color: Theme.accent
                }

                Item {
                    anchors.fill: parent
                    visible: !root._hasSelection

                    Rectangle {
                        width: 58
                        height: 58
                        radius: 18
                        anchors.centerIn: parent
                        color: Theme.accent

                        Rectangle {
                            width: 24
                            height: 24
                            radius: 8
                            anchors.centerIn: parent
                            color: Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.16)
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: mainPreview
                acceptedButtons: Qt.LeftButton
                enabled: root._hasSelection
                onClicked: {
                    root.forceActiveFocus()
                    root._applySelected()
                }
                onWheel: (event) => {
                    root._selectRelative(event.angleDelta.y < 0 ? 1 : -1)
                    event.accepted = true
                }
            }

            Item {
                anchors.fill: parent
                visible: root._isAnimating
                clip: true

                ClippingRectangle {
                    readonly property var rect: heroArea._animatedRect("prev")
                    x: rect.x
                    y: rect.y
                    width: rect.w
                    height: rect.h
                    radius: heroArea._previewRadius
                    color: Theme.accent
                    z: root._animDir < 0 ? 3 : 1
                    visible: root._animDir < 0 || root._animDir > 0

                    Image {
                        anchors.fill: parent
                        source: heroArea._animatedPath("prev") ? "file://" + heroArea._animatedPath("prev") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: source !== ""
                    }
                }

                ClippingRectangle {
                    readonly property var rect: heroArea._animatedRect("current")
                    x: rect.x
                    y: rect.y
                    width: rect.w
                    height: rect.h
                    radius: heroArea._previewRadius
                    color: Theme.surface
                    z: 2

                    Image {
                        anchors.fill: parent
                        source: heroArea._animatedPath("current") ? "file://" + heroArea._animatedPath("current") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: source !== ""
                    }

                }

                ClippingRectangle {
                    readonly property var rect: heroArea._animatedRect("next")
                    x: rect.x
                    y: rect.y
                    width: rect.w
                    height: rect.h
                    radius: heroArea._previewRadius
                    color: Theme.accent
                    z: root._animDir > 0 ? 3 : 1

                    Image {
                        anchors.fill: parent
                        source: heroArea._animatedPath("next") ? "file://" + heroArea._animatedPath("next") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: source !== ""
                    }

                }

                ClippingRectangle {
                    readonly property var rect: heroArea._animatedRect("incoming")
                    x: rect.x
                    y: rect.y
                    width: rect.w
                    height: rect.h
                    radius: heroArea._previewRadius
                    color: Theme.accent
                    z: 0

                    Image {
                        anchors.fill: parent
                        source: heroArea._animatedPath("incoming") ? "file://" + heroArea._animatedPath("incoming") : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        visible: source !== ""
                    }
                }
            }
        }
    }
}
