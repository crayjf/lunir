import QtQuick 2.15
import Quickshell.Io 0.1
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    property string _previewPath: ""
    property var    _candidates:  []

    // ── Scan wallpaper folder ─────────────────────────────────────────────────
    Process {
        id: scanProc
        property string folder: ""
        command: ["bash", "-c",
            "f=${1/#~/$HOME}; find \"$f\" -maxdepth 2 -type f" +
            " \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort",
            "--", scanProc.folder]
        running: false
        stdout: StdioCollector { id: scanStdio }
        onExited: {
            const current = Config.wallpaper.current || ""
            const all = scanStdio.text.trim().split("\n").filter(function(l) { return l.trim() })
            root._candidates = all.filter(function(p) { return p !== current })
            root._pickRandom()
        }
    }

    function _refreshPreview() {
        scanProc.folder = Config.wallpaper.folder || "~/Pictures/Wallpaper"
        scanProc.running = true
    }

    function _pickRandom() {
        if (_candidates.length === 0) {
            _previewPath = Config.wallpaper.current || ""
            return
        }
        _previewPath = _candidates[Math.floor(Math.random() * _candidates.length)]
    }

    onVisibleChanged: { if (visible) _refreshPreview() }
    Component.onCompleted: _refreshPreview()

    // ── UI ────────────────────────────────────────────────────────────────────
    Image {
        anchors.fill: parent
        source: root._previewPath ? "file://" + root._previewPath : ""
        fillMode: Image.PreserveAspectCrop
        clip: true
        visible: root._previewPath !== ""
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(1,1,1,0.05)
        visible: root._previewPath === ""
        Text {
            anchors.centerIn: parent
            text: "NO WALLPAPER"
            font.pixelSize: 10; font.letterSpacing: 2
            color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.4)
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            if (root._previewPath) {
                Config.updateWallpaper({ current: root._previewPath })
                ModuleControllers.hide("overlay")
            }
        }
    }
}
