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

    WallpaperScene {
        id: wallpaperScene
        anchors.fill: parent
        screen: win.screen
        includeDesktopWidgets: false
        cacheImage: false
        imageSourceWidth: win.width
        imageSourceHeight: win.height
    }

    DesktopGridOverlay {
        id: desktopGridCanvas
        anchors.fill: parent
        z: 1
        visible: DesktopState.editMode && win.screen === Quickshell.screens[0]
    }

    DesktopWidgetLayer {
        anchors.fill: parent
        z: 2
        screen: win.screen
        interactive: false
        visible: !DesktopState.editMode
    }
}
