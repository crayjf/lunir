import QtQuick 2.15
import Quickshell 0.1
import Quickshell.Wayland 0.1
import "../lib"

// Base layer-shell window for standalone modules.
// Usage: set moduleId, layer, anchors, margins, exclusionMode, then place content inside.
PanelWindow {
    id: win

    property string moduleId: ""

    visible: false

    property real fadeOpacity: 0.0
    Behavior on fadeOpacity {
        NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
    }
    onFadeOpacityChanged: {
        if (fadeOpacity <= 0.0) visible = false
    }

    function show() {
        visible = true
        fadeOpacity = 1.0
    }

    function hide() {
        fadeOpacity = 0.0
    }

    function toggle() {
        if (fadeOpacity > 0.0) hide()
        else show()
    }

    Component.onCompleted: {
        if (moduleId) {
            ModuleControllers.register(moduleId, {
                "show":      function() { win.show() },
                "hide":      function() { win.hide() },
                "toggle":    function() { win.toggle() },
                "isVisible": function() { return win.fadeOpacity > 0 }
            })
        }
    }

    Component.onDestruction: {
        if (moduleId) ModuleControllers.unregister(moduleId)
    }
}
