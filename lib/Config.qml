pragma Singleton
import QtQuick 2.15
import Quickshell.Io 0.1

QtObject {
    id: root

    // ── Exposed state ──────────────────────────────────────────────────────
    property var theme: ({})
    property var modules: []
    property var animation: ({})
    property var wallpaper: ({})

    // ── Defaults ───────────────────────────────────────────────────────────
    readonly property var _defaultTheme: ({
        overlayBackgroundEnabled: true,
        overlayBackground: "rgba(0,0,0,0)",
        widgetBackground: "rgba(30,30,46,0.85)",
        widgetOpacity: 1.0,
        widgetBorderColor: "rgba(137,180,250,0.5)",
        widgetBorderWidth: 1,
        widgetBorderRadius: 12,
        textColor: "#cdd6f4",
        accentColor: "#89b4fa",
    })

    readonly property var _defaultAnimation: ({
        enabled: true,
        duration: 200,
        type: "crossfade",
    })

    readonly property var _defaultWallpaper: ({
        current: "",
        folder: "~/Pictures/Wallpaper",
        fit: "cover",
    })

    readonly property var _defaultModules: ([
        {
            id: "default-empty",
            type: "empty",
            enabled: true,
            mode: "canvas",
            x: 100, y: 100, width: 300, height: 200,
        }
    ])

    // ── Config path (shell-safe, no StandardPaths dependency) ─────────────
    readonly property string _configFile: "$HOME/.config/lunir-qs/config.json"
    readonly property string _configDir:  "$HOME/.config/lunir-qs"

    // ── File reader ────────────────────────────────────────────────────────
    property Process _readProc: Process {
        id: readProc
        running: false
        command: ["sh", "-c", "cat \"$HOME/.config/lunir-qs/config.json\""]
        stdout: StdioCollector { id: readStdio }
        onExited: (code) => {
            if (code !== 0) {
                root._applyDefaults()
                root._doSave()
                return
            }
            root._parseConfig(readStdio.text)
        }
    }

    function _parseConfig(raw) {
        try {
            if (!raw || raw.trim() === "") {
                _applyDefaults()
                _doSave()
                return
            }
            const parsed = JSON.parse(raw)
            if (!parsed.version || parsed.version < 2 || parsed.widgets) {
                const migrated = _migrateV1(parsed)
                _apply(migrated)
                _doSave()
                return
            }
            _apply(parsed)
        } catch (e) {
            console.error("lunir: config.json invalid, using defaults:", e)
            _applyDefaults()
        }
    }

    function _migrateV1(parsed) {
        const oldWidgets = parsed.widgets || []
        const newModules = oldWidgets.map(w => Object.assign({ mode: "canvas" }, w))
        return {
            version: 2,
            theme: Object.assign({}, _defaultTheme, parsed.theme || {}),
            modules: newModules.length > 0 ? newModules : _defaultModules,
            animation: Object.assign({}, _defaultAnimation, parsed.animation || {}),
            wallpaper: Object.assign({}, _defaultWallpaper, parsed.wallpaper || {}),
        }
    }

    function _applyDefaults() {
        theme = Object.assign({}, _defaultTheme)
        modules = JSON.parse(JSON.stringify(_defaultModules))
        animation = Object.assign({}, _defaultAnimation)
        wallpaper = Object.assign({}, _defaultWallpaper)
    }

    function _apply(parsed) {
        theme = Object.assign({}, _defaultTheme, parsed.theme || {})
        modules = Array.isArray(parsed.modules) && parsed.modules.length > 0
            ? parsed.modules
            : JSON.parse(JSON.stringify(_defaultModules))
        animation = Object.assign({}, _defaultAnimation, parsed.animation || {})
        wallpaper = Object.assign({}, _defaultWallpaper, parsed.wallpaper || {})
    }

    // ── Save debounce ──────────────────────────────────────────────────────
    property Timer _saveTimer: Timer {
        interval: 500
        repeat: false
        onTriggered: root._doSave()
    }

    function _scheduleSave() {
        _saveTimer.restart()
    }

    property Process _saveProc: Process {
        id: saveProc
        running: false
        property string _pendingContent: ""
        command: ["sh", "-c",
            "mkdir -p \"$HOME/.config/lunir-qs\" && printf '%s' \"$1\" > \"$HOME/.config/lunir-qs/config.json\"",
            "sh", saveProc._pendingContent]
    }

    function _doSave() {
        const data = {
            version: 2,
            theme: theme,
            modules: modules,
            animation: animation,
            wallpaper: wallpaper,
        }
        _saveProc._pendingContent = JSON.stringify(data, null, 2)
        _saveProc.running = true
    }

    // ── Public mutation API ────────────────────────────────────────────────

    function updateModule(id, updates) {
        modules = modules.map(m => m.id === id ? Object.assign({}, m, updates) : m)
        _scheduleSave()
    }

    function addModule(mod) {
        modules = [...modules, mod]
        _scheduleSave()
    }

    function removeModule(id) {
        modules = modules.filter(m => m.id !== id)
        _scheduleSave()
    }

    function enableModule(id) {
        updateModule(id, { enabled: true })
    }

    function disableModule(id) {
        updateModule(id, { enabled: false })
    }

    function updateTheme(updates) {
        theme = Object.assign({}, theme, updates)
        _scheduleSave()
    }

    function updateWallpaper(updates) {
        wallpaper = Object.assign({}, wallpaper, updates)
        _scheduleSave()
    }

    function getModuleById(id) {
        return modules.find(m => m.id === id) || null
    }

    // ── Boot ───────────────────────────────────────────────────────────────
    Component.onCompleted: {
        _applyDefaults()
        readProc.running = true
    }
}
