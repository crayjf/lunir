pragma Singleton
import QtQuick 2.15
import Quickshell

// Runtime registry: module-id → { show, hide, toggle, isVisible }
// Standalone modules register on Component.onCompleted.
// IPC handler and overlay click-to-close use this.

Singleton {
    id: root

    property var _controllers: ({})

    function register(id, controller) {
        const copy = Object.assign({}, _controllers)
        copy[id] = controller
        _controllers = copy
    }

    function unregister(id) {
        const copy = Object.assign({}, _controllers)
        delete copy[id]
        _controllers = copy
    }

    function show(id) {
        const c = _controllers[id]
        if (c) c.show()
        else console.warn("ModuleControllers.show: unknown id", id)
    }

    function hide(id) {
        const c = _controllers[id]
        if (c) c.hide()
        else console.warn("ModuleControllers.hide: unknown id", id)
    }

    function toggle(id) {
        const c = _controllers[id]
        if (c) c.toggle()
        else console.warn("ModuleControllers.toggle: unknown id", id)
    }

    function isVisible(id) {
        const c = _controllers[id]
        return c ? c.isVisible() : false
    }
}
