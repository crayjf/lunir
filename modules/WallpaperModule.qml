import QtQuick 2.15
import QtQuick.Controls 2.15
import Quickshell.Io
import Quickshell.Widgets
import "../lib"

Item {
    id: root
    focus: visible

    property var moduleConfig: null

    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property color _mutedText: Theme.textMuted
    readonly property color _softText: Theme.textMuted
    readonly property var _cfg: moduleConfig ? (moduleConfig.props || {}) : ({})
    readonly property bool _nativePanel: _cfg.nativePanel === true

    readonly property string _wallpaperFolder: Config.wallpaper.folder || "~/Pictures/Wallpaper"
    readonly property string _currentWallpaper: Config.wallpaper.current || ""
    readonly property string _previewPath: (_selectedIdx >= 0 && _selectedIdx < _files.length) ? _files[_selectedIdx] : ""
    readonly property bool _hasSelection: _previewPath !== ""
    readonly property bool _previewIsCurrent: _hasSelection && _previewPath === _currentWallpaper
    property var _files: []
    property int _selectedIdx: -1

    function _basename(path) {
        if (!path) return ""
        const parts = String(path).split("/")
        return parts.length > 0 ? parts[parts.length - 1] : path
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
        if (_selectedIdx < 0) {
            _selectIdx(0)
            return
        }

        const next = (_selectedIdx + step + _files.length) % _files.length
        _selectIdx(next)
    }

    function _selectRandom() {
        if (_files.length === 0) return
        if (_files.length === 1) {
            _selectIdx(0)
            return
        }

        let next = _selectedIdx
        while (next === _selectedIdx)
            next = Math.floor(Math.random() * _files.length)
        _selectIdx(next)
    }

    function _applySelected() {
        if (_hasSelection)
            Config.updateWallpaper({ current: _previewPath })
    }

    function _applyRandom() {
        _selectRandom()
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
            root._files = scanStdio.text.trim().split("\n").filter(function(line) { return line.trim().length > 0 })
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

    Item {
        id: heroArea
        anchors.fill: parent

            ClippingRectangle {
                anchors.left: prevButton.right
                anchors.right: nextButton.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                radius: 18
                color: Theme.surface

                Image {
                    anchors.fill: parent
                    source: root._hasSelection ? "file://" + root._previewPath : ""
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    visible: root._hasSelection
                }

                Rectangle {
                    anchors.fill: parent
                    visible: !root._hasSelection
                    color: Theme.surfaceRaised
                }

                Rectangle {
                    anchors.fill: parent
                    color: root._hasSelection ? "#00000075" : "transparent"
                }

                Item {
                    anchors.fill: parent
                    visible: !root._hasSelection

                    Rectangle {
                        width: 58
                        height: 58
                        radius: 18
                        anchors.centerIn: parent
                        color: Theme.surfaceRaised

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
                anchors.left: prevButton.right
                anchors.right: nextButton.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: 8
                anchors.rightMargin: 8
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

            Rectangle {
                id: randomChip
                anchors.right: nextButton.left
                anchors.bottom: parent.bottom
                anchors.rightMargin: 18
                anchors.bottomMargin: 10
                width: randomLabel.implicitWidth + 18
                height: 24
                radius: 12
                opacity: root._files.length > 0 ? 1.0 : 0.45
                color: randomMouse.containsMouse && root._files.length > 0
                    ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.28)
                    : Theme.track

                Text {
                    id: randomLabel
                    anchors.centerIn: parent
                    text: "RANDOM"
                    font.family: Theme.fontFamily
                    font.pixelSize: 8
                    font.letterSpacing: 1.4
                    color: root._textColor
                }

                MouseArea {
                    id: randomMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root._files.length > 0
                    onClicked: {
                        root.forceActiveFocus()
                        root._applyRandom()
                    }
                }
            }

            Rectangle {
                id: prevButton
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 58
                radius: 14
                opacity: root._files.length > 1 ? 1.0 : 0.38
                color: prevMouse.containsMouse && root._files.length > 1
                    ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.18)
                    : Theme.surfaceRaised

                Canvas {
                    anchors.centerIn: parent
                    width: 14
                    height: 18
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = root._textColor
                        ctx.lineWidth = 2.2
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(10, 4)
                        ctx.lineTo(5, 9)
                        ctx.lineTo(10, 14)
                        ctx.stroke()
                    }
                }

                MouseArea {
                    id: prevMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root._files.length > 1
                    onClicked: {
                        root.forceActiveFocus()
                        root._selectRelative(-1)
                    }
                }
            }

            Rectangle {
                id: nextButton
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 46
                height: 58
                radius: 14
                opacity: root._files.length > 1 ? 1.0 : 0.38
                color: nextMouse.containsMouse && root._files.length > 1
                    ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.18)
                    : Theme.surfaceRaised

                Canvas {
                    anchors.centerIn: parent
                    width: 14
                    height: 18
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)
                        ctx.strokeStyle = root._textColor
                        ctx.lineWidth = 2.2
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(4, 4)
                        ctx.lineTo(9, 9)
                        ctx.lineTo(4, 14)
                        ctx.stroke()
                    }
                }

                MouseArea {
                    id: nextMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: root._files.length > 1
                    onClicked: {
                        root.forceActiveFocus()
                        root._selectRelative(1)
                    }
                }
            }
        }
}
