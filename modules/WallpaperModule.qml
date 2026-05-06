import QtQuick 2.15
import QtQuick.Controls 2.15
import Quickshell.Widgets
import "../lib"

Item {
    id: root
    focus: visible

    property var moduleConfig: null
    readonly property int preferredHeight: Math.max(96, Math.min(150, Math.round(width * 0.24)))
    implicitHeight: preferredHeight

    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")

    readonly property string _wallpaperFolder: Config.wallpaper.folder || "~/Pictures/Wallpaper"
    readonly property string _currentWallpaper: Config.wallpaper.current || ""
    readonly property var _wallpaperState: WallpaperState
    readonly property var _files: _wallpaperState.files || []
    readonly property string _previewPath: (_selectedIdx >= 0 && _selectedIdx < _files.length) ? _files[_selectedIdx] : ""
    readonly property bool _hasSelection: _previewPath !== ""
    readonly property bool _hasMultiple: _files.length > 1
    readonly property string _previousPath: _hasMultiple && _selectedIdx >= 0 ? _files[(_selectedIdx - 1 + _files.length) % _files.length] : ""
    readonly property string _nextPath: _hasMultiple && _selectedIdx >= 0 ? _files[(_selectedIdx + 1) % _files.length] : ""
    readonly property bool _isAnimating: slideAnim.running
    readonly property var _preloadPaths: {
        if (_selectedIdx < 0 || _files.length === 0)
            return [];
        const paths = [];
        const preloadOffsets = [-2, -1, 0, 1, 2];
        if (_isAnimating)
            preloadOffsets.push(_animDir > 0 ? 3 : -3);
        for (const offset of preloadOffsets) {
            const path = _pathAt(_selectedIdx, offset);
            if (path && paths.indexOf(path) === -1)
                paths.push(path);
        }
        return paths;
    }
    property int _selectedIdx: -1
    property int _animStartIdx: -1
    property int _animDir: 0
    property real _slideProgress: 0.0
    property bool _animatingTransition: false
    property string _selectionPathHint: ""

    function _wrapIndex(idx) {
        if (_files.length <= 0)
            return -1;
        return (idx % _files.length + _files.length) % _files.length;
    }
    function _pathAt(baseIdx, offset) {
        const wrapped = _wrapIndex(baseIdx + offset);
        return wrapped >= 0 ? _files[wrapped] : "";
    }
    function _syncSelection(preferredPath) {
        _animatingTransition = false;
        _animStartIdx = -1;
        _animDir = 0;
        _slideProgress = 0;
        if (_files.length === 0) {
            _selectedIdx = -1;
            _selectionPathHint = "";
            return;
        }

        const preferred = preferredPath || _selectionPathHint || _currentWallpaper;
        const idx = preferred ? _files.indexOf(preferred) : -1;
        _selectedIdx = idx >= 0 ? idx : Math.max(0, Math.min(_selectedIdx, _files.length - 1));
        _selectionPathHint = (_selectedIdx >= 0 && _selectedIdx < _files.length) ? _files[_selectedIdx] : "";
    }

    function _refreshWallpapers(preferredPath) {
        if (_wallpaperState.scanRunning)
            return;
        _wallpaperState.refresh(_wallpaperFolder, preferredPath || _selectionPathHint || _currentWallpaper, _currentWallpaper);
    }

    function _selectIdx(idx) {
        if (_files.length === 0)
            return;
        _selectedIdx = Math.max(0, Math.min(idx, _files.length - 1));
        _selectionPathHint = _previewPath;
    }

    function _selectRelative(step) {
        if (_files.length === 0)
            return;
        if (_isAnimating)
            return;
        if (_selectedIdx < 0) {
            _selectIdx(0);
            return;
        }

        _animStartIdx = _selectedIdx;
        _animDir = step < 0 ? -1 : 1;
        _animatingTransition = true;
        _selectedIdx = _wrapIndex(_selectedIdx + _animDir);
        _slideProgress = 0;
        _selectionPathHint = _previewPath;
        slideAnim.start();
    }

    function _applySelected() {
        if (_hasSelection)
            Config.updateWallpaper({
                current: _previewPath
            });
    }

    function _deleteSelected() {
        if (!_hasSelection || _wallpaperState.deleteRunning || _isAnimating)
            return;
        const deletingPath = _previewPath;
        const deletingCurrent = deletingPath === _currentWallpaper;
        let fallbackPath = "";

        if (_files.length > 1) {
            const fallbackIdx = _selectedIdx < _files.length - 1 ? _selectedIdx + 1 : _selectedIdx - 1;
            fallbackPath = _files[Math.max(0, fallbackIdx)] || "";
        }

        _wallpaperState.deleteWallpaper(deletingPath, fallbackPath, deletingCurrent, _currentWallpaper);
    }

    onVisibleChanged: {
        if (visible) {
            if (_files.length === 0)
                _refreshWallpapers();
            forceActiveFocus();
        }
    }

    on_WallpaperFolderChanged: {
        if (_wallpaperFolder !== _wallpaperState.lastScannedFolder)
            _refreshWallpapers(_currentWallpaper);
    }

    Connections {
        target: Config
        function onWallpaperChanged() {
            if (!_wallpaperState.scanRunning)
                root._syncSelection(root._currentWallpaper);
        }
    }

    Connections {
        target: _wallpaperState
        function onFilesChanged() {
            root._syncSelection(_wallpaperState.preferredSelectionPath || root._selectionPathHint || root._currentWallpaper);
        }
    }

    Keys.onLeftPressed: root._selectRelative(-1)
    Keys.onRightPressed: root._selectRelative(1)
    Keys.onReturnPressed: root._applySelected()
    Keys.onPressed: event => {
        if (event.key === Qt.Key_X && (event.modifiers & Qt.ControlModifier)) {
            root._deleteSelected();
            event.accepted = true;
        }
    }

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
                root._slideProgress = 0;
                root._animStartIdx = -1;
                root._animDir = 0;
                root._animatingTransition = false;
            }
        }
    }

    Item {
        id: heroArea
        anchors.fill: parent
        readonly property real _centerGap: 12
        readonly property real _previewRadius: 18
        readonly property real _previewHeight: Math.min(previewFrame.height, Math.floor(Math.max(0, previewFrame.width - heroArea._centerGap * 4) * 3 / 16))
        readonly property real _centerWidth: Math.round(heroArea._previewHeight * 16 / 9)
        readonly property real _innerWidth: Math.round(heroArea._centerWidth * 0.8)
        readonly property real _outerWidth: Math.max(0, Math.round((previewFrame.width - heroArea._centerGap * 4 - heroArea._centerWidth - heroArea._innerWidth * 2) / 2))

        function _lerp(a, b, t) {
            return a + (b - a) * t;
        }
        function _slotRect(offset) {
            const y = previewFrame.y + Math.round((previewFrame.height - heroArea._previewHeight) / 2);
            const leftX = previewFrame.x;
            const outerLeftX = leftX;
            const leftMidX = outerLeftX + heroArea._outerWidth + heroArea._centerGap;
            const centerX = leftMidX + heroArea._innerWidth + heroArea._centerGap;
            const rightMidX = centerX + heroArea._centerWidth + heroArea._centerGap;
            const outerRightX = rightMidX + heroArea._innerWidth + heroArea._centerGap;

            switch (offset) {
            case -3:
                return {
                    x: outerLeftX - heroArea._outerWidth - heroArea._centerGap,
                    y: y,
                    w: heroArea._outerWidth,
                    h: heroArea._previewHeight
                };
            case -2:
                return {
                    x: outerLeftX,
                    y: y,
                    w: heroArea._outerWidth,
                    h: heroArea._previewHeight
                };
            case -1:
                return {
                    x: leftMidX,
                    y: y,
                    w: heroArea._innerWidth,
                    h: heroArea._previewHeight
                };
            case 0:
                return {
                    x: centerX,
                    y: y,
                    w: heroArea._centerWidth,
                    h: heroArea._previewHeight
                };
            case 1:
                return {
                    x: rightMidX,
                    y: y,
                    w: heroArea._innerWidth,
                    h: heroArea._previewHeight
                };
            case 2:
                return {
                    x: outerRightX,
                    y: y,
                    w: heroArea._outerWidth,
                    h: heroArea._previewHeight
                };
            case 3:
                return {
                    x: outerRightX + heroArea._outerWidth + heroArea._centerGap,
                    y: y,
                    w: heroArea._outerWidth,
                    h: heroArea._previewHeight
                };
            default:
                return {
                    x: centerX,
                    y: y,
                    w: heroArea._centerWidth,
                    h: heroArea._previewHeight
                };
            }
        }
        function _mixRect(fromRect, toRect) {
            return {
                x: _lerp(fromRect.x, toRect.x, root._slideProgress),
                y: _lerp(fromRect.y, toRect.y, root._slideProgress),
                w: _lerp(fromRect.w, toRect.w, root._slideProgress),
                h: _lerp(fromRect.h, toRect.h, root._slideProgress)
            };
        }
        function _staticOffsets() {
            return [-2, -1, 0, 1, 2];
        }
        function _animatedOffsets() {
            return root._animDir > 0 ? [-2, -1, 0, 1, 2, 3] : [-3, -2, -1, 0, 1, 2];
        }
        function _animatedRect(offset) {
            const targetOffset = offset - root._animDir;
            return _mixRect(_slotRect(offset), _slotRect(targetOffset));
        }
        function _animatedPath(offset) {
            return root._animStartIdx >= 0 ? root._pathAt(root._animStartIdx, offset) : "";
        }
        function _cardOpacity(offset) {
            if (offset === 0)
                return 1.0;
            if (Math.abs(offset) === 1)
                return 0.92;
            return 0.82;
        }
        function _cardColor(offset) {
            return offset === 0 ? Theme.surface : Theme.accent;
        }

        readonly property int _decodeWidth: Math.max(256, Math.round(heroArea._centerWidth * 1.1))
        readonly property int _decodeHeight: Math.max(144, Math.round(heroArea._previewHeight * 1.1))

        Item {
            id: wallpaperContent
            anchors.fill: parent

            Item {
                width: 1
                height: 1
                opacity: 0
                enabled: false

                Repeater {
                    model: root._preloadPaths

                    delegate: Image {
                        required property var modelData
                        width: 1
                        height: 1
                        source: modelData ? "file://" + modelData : ""
                        sourceSize.width: heroArea._decodeWidth
                        sourceSize.height: heroArea._decodeHeight
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: true
                        mipmap: true
                    }
                }
            }

            Item {
                id: previewFrame
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 2
                anchors.rightMargin: 2
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10
                height: parent.height * 0.85
            }

            Item {
                anchors.fill: parent
                visible: !root._animatingTransition

                Repeater {
                    model: heroArea._staticOffsets()

                    delegate: WallpaperCard {
                        required property var modelData
                        readonly property var rect: heroArea._slotRect(modelData)
                        x: rect.x
                        y: rect.y
                        width: rect.w
                        height: rect.h
                        z: 10 - Math.abs(modelData)
                        sourcePath: root._pathAt(root._selectedIdx, modelData)
                        offset: modelData
                        cardOpacity: heroArea._cardOpacity(modelData)
                        cardColor: heroArea._cardColor(modelData)
                        interactive: !root._isAnimating
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: root._animatingTransition
                clip: true

                Repeater {
                    model: heroArea._animatedOffsets()

                    delegate: WallpaperCard {
                        required property var modelData
                        readonly property var rect: heroArea._animatedRect(modelData)
                        x: rect.x
                        y: rect.y
                        width: rect.w
                        height: rect.h
                        z: 10 - Math.abs(modelData - root._animDir)
                        sourcePath: heroArea._animatedPath(modelData)
                        offset: modelData - root._animDir
                        cardOpacity: heroArea._cardOpacity(modelData - root._animDir)
                        cardColor: heroArea._cardColor(modelData - root._animDir)
                        interactive: false
                    }
                }
            }
        }
    }

    component WallpaperCard: Item {
        id: card
        property string sourcePath: ""
        property int offset: 0
        property real cardOpacity: 1.0
        property color cardColor: Theme.surface
        property bool interactive: true

        opacity: cardOpacity

        ClippingRectangle {
            anchors.fill: parent
            radius: heroArea._previewRadius
            color: card.cardColor

            Image {
                anchors.fill: parent
                source: card.sourcePath ? "file://" + card.sourcePath : ""
                sourceSize.width: heroArea._decodeWidth
                sourceSize.height: heroArea._decodeHeight
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                mipmap: true
                visible: card.sourcePath !== ""
            }

            Rectangle {
                anchors.fill: parent
                visible: card.sourcePath === ""
                color: card.cardColor
            }

            Item {
                anchors.fill: parent
                visible: card.offset === 0 && card.sourcePath === ""

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
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            enabled: card.interactive && (card.offset === 0 ? root._hasSelection : root._files.length > 1)
            onClicked: {
                root.forceActiveFocus();
                if (card.offset === 0) {
                    root._applySelected();
                    return;
                }
                if (root._selectedIdx >= 0)
                    root._selectIdx(root._wrapIndex(root._selectedIdx + card.offset));
            }
            onWheel: event => {
                root._selectRelative(event.angleDelta.y < 0 ? 1 : -1);
                event.accepted = true;
            }
        }
    }
}
