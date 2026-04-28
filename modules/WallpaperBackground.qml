import QtQuick 2.15
import Quickshell
import Quickshell.Wayland
import "../lib"

// Always-visible background wallpaper window (BACKGROUND layer).
PanelWindow {
    id: win

    WlrLayershell.layer: WlrLayershell.Background
    WlrLayershell.namespace: "wallpaper"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "black"

    visible: true

    Image {
        anchors.fill: parent
        source: Config.wallpaper.current ? expandPath(Config.wallpaper.current) : ""
        fillMode: fitMode(Config.wallpaper.fit)
        sourceSize.width: win.width
        sourceSize.height: win.height
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
