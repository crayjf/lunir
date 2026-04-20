import QtQuick 2.15
import Quickshell 0.1
import Quickshell.Wayland 0.1
import "../lib"

// Always-visible background wallpaper window (BACKGROUND layer).
PanelWindow {
    id: win

    WlrLayershell.layer: WlrLayershell.Background
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal

    visible: {
        const m = Config.modules.find(function(m) { return m.type === "wallpaper-background" })
        return !m || m.enabled !== false
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000"
    }

    Image {
        anchors.fill: parent
        source: Config.wallpaper.current ? expandPath(Config.wallpaper.current) : ""
        fillMode: fitMode(Config.wallpaper.fit)
        asynchronous: true
        cache: false
    }

    function expandPath(p) { return p }

    function fitMode(fit) {
        switch (fit) {
            case "fill":       return Image.Stretch
            case "contain":    return Image.PreserveAspectFit
            case "scale-down": return Image.PreserveAspectFit
            default:           return Image.PreserveAspectCrop  // "cover"
        }
    }
}
