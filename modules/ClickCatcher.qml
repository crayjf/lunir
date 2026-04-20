import QtQuick 2.15
import Quickshell 0.1
import Quickshell.Wayland 0.1
import "../lib"

// Fullscreen transparent surface that sits behind all WidgetWindows.
// Holds exclusive keyboard focus for the overlay so Escape and Ctrl+N work.
// A click anywhere on this surface (i.e. not on a widget) closes the overlay.
// Also hosts the drag-grid overlay (shown by WidgetWindow drag/resize in Step 5).
PanelWindow {
    id: win

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "lunir-qs"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    screen: Quickshell.screens.find(function(s) { return s.name === "DP-1" }) ?? Quickshell.screens[0]

    visible: false

    property real fadeOpacity: 0.0
    Behavior on fadeOpacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    onFadeOpacityChanged: { if (fadeOpacity <= 0.0) win.visible = false }

    // ── Background tint (only when overlayBackgroundEnabled) ───────────────────
    Rectangle {
        anchors.fill: parent
        visible: Theme.overlayBackgroundEnabled
        color: Qt.rgba(Theme.overlayBackground.r, Theme.overlayBackground.g,
                       Theme.overlayBackground.b, Theme.overlayBackground.a * win.fadeOpacity)
    }

    // ── Click-to-close ─────────────────────────────────────────────────────────
    MouseArea {
        anchors.fill: parent
        onClicked: ModuleControllers.hide("overlay")
    }

    // ── Keyboard ───────────────────────────────────────────────────────────────
    Item {
        anchors.fill: parent
        focus: true

        Keys.onEscapePressed: ModuleControllers.hide("overlay")

        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_N && (event.modifiers & Qt.ControlModifier)) {
                _spawnNewNote()
                event.accepted = true
            }
        }
    }

    // ── New note ───────────────────────────────────────────────────────────────
    function _spawnNewNote() {
        const W = 270, H = 220
        const id = "note-" + Date.now()
        Config.addModule({
            id: id,
            type: "note",
            enabled: true,
            mode: "canvas",
            x: Math.round((win.width  - W) / 2),
            y: Math.round((win.height - H) / 2),
            width: W,
            height: H,
            props: { title: "", body: "" }
        })
    }

    // ── Show / hide ───────────────────────────────────────────────────────────
    function show() {
        visible = true
        fadeOpacity = 1.0
        forceActiveFocus()
    }

    function hide() {
        fadeOpacity = 0.0
    }

    // ── ModuleControllers registration ────────────────────────────────────────
    Component.onCompleted: {
        ModuleControllers.register("click-catcher", {
            "show":      function() { win.show() },
            "hide":      function() { win.hide() },
            "toggle":    function() { if (win.fadeOpacity > 0) win.hide(); else win.show() },
            "isVisible": function() { return win.fadeOpacity > 0 }
        })
    }

    Component.onDestruction: { ModuleControllers.unregister("click-catcher") }
}
