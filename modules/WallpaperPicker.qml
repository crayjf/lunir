import QtQuick 2.15
import QtQuick.Controls 2.15
import Quickshell 0.1
import Quickshell.Wayland 0.1
import Quickshell.Io 0.1
import "../lib"

// Full-screen wallpaper browser.
// Left: thumbnail list. Right: large preview.
// Single click → preview. Enter/double-click → apply + close.
// Delete key → delete file from disk.
// Registered as "wallpaper-picker" in ModuleControllers.
PanelWindow {
    id: win

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "lunir-qs"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal

    visible: false

    property real fadeOpacity: 0.0
    Behavior on fadeOpacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    onFadeOpacityChanged: { if (fadeOpacity <= 0.0) { visible = false; _clearList() } }

    // ── State ─────────────────────────────────────────────────────────────────
    property var    currentFiles: []
    property int    selectedIdx: -1
    property string previewedPath: ""

    // ── Content ───────────────────────────────────────────────────────────────
    Rectangle {
        id: contentRoot
        anchors.fill: parent
        opacity: win.fadeOpacity
        focus: true
        color: Qt.rgba(
            Theme.overlayBackground.r,
            Theme.overlayBackground.g,
            Theme.overlayBackground.b,
            0.96)

        Keys.onEscapePressed: { if (win.fadeOpacity > 0) win._doHide() }
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Delete) {
                win._deleteSelected(); event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                win._applyAndClose(); event.accepted = true
            } else if (event.key === Qt.Key_Down) {
                win._selectIdx(win.selectedIdx + 1); event.accepted = true
            } else if (event.key === Qt.Key_Up) {
                win._selectIdx(win.selectedIdx - 1); event.accepted = true
            }
        }

        Column {
            anchors { fill: parent; margins: 36 }
            spacing: 16

            Text {
                text: "WALLPAPER"
                font.pixelSize: 14
                font.letterSpacing: 3
                color: Theme.textColor
            }

            Row {
                width: parent.width
                height: parent.height - 40
                spacing: 28

                // Thumbnail strip
                Column {
                    width: 300
                    height: parent.height
                    spacing: 8

                    Text {
                        id: folderLabel
                        text: Config.wallpaper.folder || ""
                        font.pixelSize: 10
                        color: Qt.rgba(Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 0.6)
                        elide: Text.ElideMiddle
                        width: parent.width
                    }

                    ListView {
                        id: thumbList
                        width: parent.width
                        height: parent.height - folderLabel.height - 8
                        spacing: 4
                        clip: true
                        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

                        model: ListModel { id: thumbListModel }

                            delegate: Rectangle {
                                width: thumbList.width
                                height: 96
                                color: index === win.selectedIdx
                                    ? Qt.rgba(Theme.accentColor.r, Theme.accentColor.g, Theme.accentColor.b, 0.2)
                                    : "transparent"
                                radius: 6

                                Image {
                                    anchors { fill: parent; margins: 3 }
                                    source: "file://" + model.path
                                    fillMode: Image.PreserveAspectCrop
                                    clip: true
                                    asynchronous: true

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "transparent"
                                        border.color: index === win.selectedIdx
                                            ? Theme.accentColor : "transparent"
                                        border.width: 2
                                        radius: 4
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { win._selectIdx(index) }
                                    onDoubleClicked: { win._applyAndClose() }
                                }
                            }
                        }
                }

                // Large preview
                Rectangle {
                    width: parent.width - 328
                    height: parent.height
                    color: "transparent"
                    radius: 8
                    clip: true

                    Image {
                        id: previewImage
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        clip: true

                        MouseArea {
                            anchors.fill: parent
                            onClicked: win._applyAndClose()
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "No preview"
                        color: Qt.rgba(Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 0.3)
                        font.pixelSize: 13
                        visible: previewImage.source.toString() === ""
                    }
                }
            }
        }
    }

    // ── Populate / clear ──────────────────────────────────────────────────────
    function _populate() {
        thumbListModel.clear()
        currentFiles = []
        selectedIdx = -1
        previewedPath = ""
        previewImage.source = ""

        const folder = Config.wallpaper.folder || ""
        const current = Config.wallpaper.current || ""

        scanProc.folder = folder
        scanProc.current = current
        scanProc.running = true
    }

    Process {
        id: scanProc
        property string folder: ""
        property string current: ""
        command: ["bash", "-c",
            "find \"" + folder.replace("~", "$HOME") + "\" -maxdepth 1 -type f " +
            "\\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' " +
            "-o -iname '*.avif' -o -iname '*.tiff' \\) 2>/dev/null | sort"]
        running: false

        stdout: StdioCollector { id: scanStdio }

        onExited: {
            const lines = scanStdio.text.trim().split("\n").filter(function(l) { return l.length > 0 })
win.currentFiles = lines

            for (let i = 0; i < lines.length; i++) {
                thumbListModel.append({ path: lines[i] })
            }

            const curIdx = lines.indexOf(scanProc.current)
            const selIdx = curIdx >= 0 ? curIdx : 0
            win.selectedIdx = selIdx

            if (lines.length > 0) {
                win.previewedPath = lines[selIdx]
                previewImage.source = "file://" + lines[selIdx]
                thumbList.positionViewAtIndex(selIdx, ListView.Center)
            }
        }
    }

    function _clearList() {
        thumbListModel.clear()
        currentFiles = []
        selectedIdx = -1
        previewedPath = ""
        previewImage.source = ""
    }

    // ── Select by index ───────────────────────────────────────────────────────
    function _selectIdx(idx) {
        if (currentFiles.length === 0) return
        const i = Math.max(0, Math.min(idx, currentFiles.length - 1))
        selectedIdx = i
        previewedPath = currentFiles[i]
        previewImage.source = "file://" + currentFiles[i]
        thumbList.positionViewAtIndex(i, ListView.Contain)
    }

    // ── Apply / delete ────────────────────────────────────────────────────────
    function _applyAndClose() {
        if (!previewedPath) return
        Config.updateWallpaper({ current: previewedPath })
        _doHide()
    }

    Process {
        id: deleteProc
        property string filePath: ""
        command: ["rm", "--", filePath]
        running: false
    }

    function _deleteSelected() {
        if (selectedIdx < 0 || selectedIdx >= currentFiles.length) return
        const path = currentFiles[selectedIdx]
        deleteProc.filePath = path
        deleteProc.running = true

        thumbListModel.remove(selectedIdx)
        currentFiles.splice(selectedIdx, 1)

        if (Config.wallpaper.current === path) Config.updateWallpaper({ current: "" })

        if (currentFiles.length === 0) { selectedIdx = -1; previewedPath = ""; previewImage.source = ""; return }
        const next = Math.min(selectedIdx, currentFiles.length - 1)
        selectedIdx = next
        previewedPath = currentFiles[next]
        previewImage.source = "file://" + currentFiles[next]
        thumbList.positionViewAtIndex(next, ListView.Center)
    }

    // ── Show / hide ───────────────────────────────────────────────────────────
    function _doShow() {
        _populate()
        visible = true
        fadeOpacity = 1.0
        contentRoot.forceActiveFocus()
    }

    function _doHide() {
        fadeOpacity = 0.0
    }

    Component.onCompleted: {
        ModuleControllers.register("wallpaper-picker", {
            "show":      function() { win._doShow() },
            "hide":      function() { win._doHide() },
            "toggle":    function() { if (win.fadeOpacity > 0) win._doHide(); else win._doShow() },
            "isVisible": function() { return win.fadeOpacity > 0 }
        })
    }

    Component.onDestruction: { ModuleControllers.unregister("wallpaper-picker") }
}
