import QtQuick 2.15
import Quickshell 0.1
import "../lib"

// Overlay orchestrator — no Wayland surface of its own.
// Spawns one WidgetWindow per enabled canvas module via Variants (instances
// survive config changes, so save timers and other state are never killed).
// Coordinates show/hide with ClickCatcher, which owns keyboard + background.
// Registered as "overlay" with ModuleControllers.
QtObject {
    id: root

    // Broadcast to all WidgetWindow delegates.
    signal showAll
    signal hideAll

    property var _canvasModules: Config.modules.filter(
        function(m) { return m.enabled && m.mode === "canvas" })

    property var _variants: Variants {
        model: root._canvasModules

        WidgetWindow {
            id: ww
            required property var modelData
            moduleConfig: modelData

            Connections {
                target: root
                function onShowAll() { ww.show() }
                function onHideAll() { ww.hide() }
            }
        }
    }

    function _doShow() {
        root.showAll()
        ModuleControllers.show("click-catcher")
    }

    function _doHide() {
        root.hideAll()
        ModuleControllers.hide("click-catcher")
        SelectedDay.reset()
    }

    Component.onCompleted: {
        ModuleControllers.register("overlay", {
            "show":      function() { if (!ModuleControllers.isVisible("click-catcher")) root._doShow() },
            "hide":      function() { if (ModuleControllers.isVisible("click-catcher"))  root._doHide() },
            "toggle":    function() {
                if (ModuleControllers.isVisible("click-catcher")) root._doHide()
                else root._doShow()
            },
            "isVisible": function() { return ModuleControllers.isVisible("click-catcher") }
        })
    }

    Component.onDestruction: { ModuleControllers.unregister("overlay") }
}
