pragma Singleton
import QtQuick 2.15
import Quickshell
import Quickshell.Io
import "ConfigUtils.js" as ConfigUtils

Singleton {
    id: root

    readonly property int schemaVersion: 4

    property var theme: ({})
    property var wallpaper: ({})
    property var weather: ({})
    property var calendar: ({})
    property var launcher: ({})
    property bool desktopWidgetsEnabled: true
    property var garmin: ({})
    property var desktopModules: ([])
    property var controlCenter: ({})
    property var backdrop: ({})
    property var cava: ({})

    readonly property var _defaultTheme: ({
        background: "#191A21FF",
        surface: "#282A36F0",

        border: "#F8F8F21F",
        text: "#F8F8F2FF",
        textMuted: "#F8F8F2B3",
        accent: "#FF79C6FF",
        track: "#F8F8F224",
        radiusSmall: 12,
        radiusLarge: 28,
        borderWidth: 1,
        fontFamily: "Inter",
    })

    readonly property var _defaultWallpaper: ({
        current: "",
        folder: "~/Pictures/Wallpaper",
        fit: "cover",
    })

    readonly property var _defaultWeather: ({
        apiKey: "",
        location: "Berlin,DE",
        units: "metric",
        refreshInterval: 30,
    })

    readonly property var _defaultCalendar: ({
        calendars: [],
        showColors: true,
        refreshInterval: 30,
    })

    readonly property var _defaultLauncher: ({
        terminalCommand: "ghostty",
        iconTheme: "",
        iconThemePaths: [],
    })

    readonly property var _defaultGarmin: ({
        email: "",
        password: "",
        refreshInterval: 10,
    })

    readonly property var _defaultDesktopModules: ([
        {
            id: "desktop-weekday",
            type: "weekday",
            enabled: true,
            x: 940,
            y: 20,
            width: 660,
            height: 110,
            widgetBackground: "#00000000",
        },
        {
            id: "desktop-dateday",
            type: "dateday",
            enabled: true,
            x: 940,
            y: 135,
            height: 40,
            widgetBackground: "#00000000",
        },
        {
            id: "desktop-datemonth",
            type: "datemonth",
            enabled: true,
            x: 1000,
            y: 135,
            height: 40,
            widgetBackground: "#00000000",
        },
        {
            id: "desktop-clock",
            type: "clock",
            enabled: true,
            x: 940,
            y: 180,
            width: 200,
            height: 200,
            widgetBackground: "#00000000",
        },
        {
            id: "desktop-progress",
            type: "progress",
            enabled: true,
            x: 940,
            y: 235,
            width: 660,
            height: 26,
            minHeight: 6,
            widgetBackground: "#00000000",
        },
        {
            id: "desktop-cava",
            type: "cava",
            enabled: true,
            height: 220,
            minHeight: 120,
            spanMonitorWidth: true,
            stickToBottom: true,
            maxHeightRatio: 0.25,
            widgetBackground: "#00000000",
        },
    ])

    readonly property var _defaultControlCenter: ({
        animationStyle: "Move",
        animationTime: 180,
    })

    readonly property var _defaultBackdrop: ({
        mode: "blur",      // "blur" | "xray" | "none"
        blur: 1.0,         // blur intensity 0.0–1.0
        blurMax: 64,       // blur radius in pixels
        saturation: -0.15, // saturation shift -1.0–1.0 (negative = desaturate)
    })

    readonly property var _defaultCava: ({
        bars: 120,
        barColor: null,
        height: 220,
    })

    readonly property string _xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string _configDir: _xdgConfigHome + "/lunir"
    readonly property string _configFile: _configDir + "/config.json"

    property bool loaded: false

    property FileView _configView: FileView {
        id: configView
        path: root._configFile
        blockLoading: true
        watchChanges: true
        onLoaded: { root._applyFromFile(); root.loaded = true }
        onFileChanged: reload()
        onLoadFailed: { root._applyDefaults(); root.loaded = true }
        onSaveFailed: (error) => console.warn("Failed to save config.json:", error)
    }

    property Timer _saveTimer: Timer {
        interval: 500
        repeat: false
        onTriggered: root._save()
    }

    property var _pendingData: null
    property Process _mkdirProc: Process {
        command: ["mkdir", "-p", root._configDir]
        onExited: (code) => {
            if (code === 0 && root._pendingData) {
                configView.setText(root._stringifyConfig(root._pendingData))
                root._pendingData = null
            }
        }
    }

    function _copy(value) {
        return ConfigUtils.copy(value)
    }

    function _merge(defaults, value) {
        return ConfigUtils.merge(defaults, value)
    }

    function _normalizeDesktopModules(value) {
        const defaults = _copy(_defaultDesktopModules)
        if (value === undefined)
            return defaults
        if (!Array.isArray(value))
            return defaults

        const source = _copy(value)
        const byId = {}
        const extras = []
        for (const module of source) {
            if (!module || typeof module !== "object")
                continue
            if (!module.id || !module.type)
                continue
            byId[module.id] = _copy(module)
        }

        const merged = defaults.map(function(defaultModule) {
            const override = byId[defaultModule.id]
            return override ? Object.assign({}, defaultModule, override) : defaultModule
        })

        for (const module of source) {
            if (!module || typeof module !== "object" || !module.id || !module.type)
                continue
            const isDefault = defaults.some(function(defaultModule) {
                return defaultModule.id === module.id
            })
            if (!isDefault)
                extras.push(_copy(module))
        }

        return merged.concat(extras)
    }

    function _normalizeControlCenter(value) {
        const input = value && typeof value === "object" ? value : {}
        return {
            animationStyle: input.animationStyle !== undefined ? input.animationStyle : _defaultControlCenter.animationStyle,
            animationTime: input.animationTime !== undefined ? input.animationTime : _defaultControlCenter.animationTime,
        }
    }

    function _normalizeBackdrop(value) {
        const input = value && typeof value === "object" ? value : {}
        return {
            mode: input.mode !== undefined ? input.mode : _defaultBackdrop.mode,
            blur: input.blur !== undefined ? input.blur : _defaultBackdrop.blur,
            blurMax: input.blurMax !== undefined ? input.blurMax : _defaultBackdrop.blurMax,
            saturation: input.saturation !== undefined ? input.saturation : _defaultBackdrop.saturation,
        }
    }

    function _applyDefaults() {
        theme = _copy(_defaultTheme)
        wallpaper = _copy(_defaultWallpaper)
        weather = _copy(_defaultWeather)
        calendar = _copy(_defaultCalendar)
        launcher = _copy(_defaultLauncher)
        desktopWidgetsEnabled = true
        desktopModules = _copy(_defaultDesktopModules)
        garmin = _copy(_defaultGarmin)
        controlCenter = _copy(_defaultControlCenter)
        backdrop = _normalizeBackdrop()
        cava = _copy(_defaultCava)
    }

    function _apply(parsed) {
        parsed = parsed || {}

        theme = _merge(_defaultTheme, parsed.theme)
        wallpaper = _merge(_defaultWallpaper, parsed.wallpaper)
        weather = _merge(_defaultWeather, parsed.weather)
        calendar = _merge(_defaultCalendar, parsed.calendar)
        launcher = _merge(_defaultLauncher, parsed.launcher)
        desktopWidgetsEnabled = parsed.desktopWidgetsEnabled !== undefined ? !!parsed.desktopWidgetsEnabled : true
        desktopModules = _normalizeDesktopModules(parsed.desktopModules)
        garmin = _merge(_defaultGarmin, parsed.garmin)
        controlCenter = _normalizeControlCenter(parsed.controlCenter)
        backdrop = _normalizeBackdrop(parsed.backdrop)
        cava = _merge(_defaultCava, parsed.cava)
    }

    function _applyFromFile() {
        const text = configView.text()
        if (!text || !text.trim()) {
            _applyDefaults()
            return
        }

        try {
            _apply(JSON.parse(_stripJsonComments(text)))
        } catch (e) {
            console.warn("Failed to parse config.json:", e)
            _applyDefaults()
        }
    }

    function _stripJsonComments(text) {
        return ConfigUtils.stripJsonComments(text)
    }

    function _compact(value, defaults) {
        return ConfigUtils.compact(value, defaults)
    }

    function _assign(data, key, value, defaults) {
        ConfigUtils.assign(data, key, value, defaults)
    }

    function _scheduleSave() {
        _saveTimer.restart()
    }

    function _buildConfigData() {
        const data = { version: schemaVersion }
        data.theme = theme
        _assign(data, "wallpaper", wallpaper, _defaultWallpaper)
        _assign(data, "weather", weather, _defaultWeather)
        _assign(data, "calendar", calendar, _defaultCalendar)
        _assign(data, "launcher", launcher, _defaultLauncher)
        _assign(data, "desktopWidgetsEnabled", desktopWidgetsEnabled, true)
        _assign(data, "desktopModules", desktopModules, _defaultDesktopModules)
        _assign(data, "garmin", garmin, _defaultGarmin)
        _assign(data, "cava", cava, _defaultCava)
        _assign(data, "backdrop", backdrop, _defaultBackdrop)
        data.controlCenter = controlCenter
        return data
    }

    function saveImmediate() {
        _saveTimer.stop()
        const data = _buildConfigData()
        configView.setText(_stringifyConfig(data))
    }

    function _save() {
        _pendingData = _buildConfigData()
        _mkdirProc.running = true
    }

    function _indent(text, spaces) {
        return ConfigUtils.indent(text, spaces)
    }

    function _appendSection(lines, key, value, isLast) {
        ConfigUtils.appendSection(lines, key, value, isLast)
    }

    function _stringifyConfig(data) {
        return ConfigUtils.stringifyConfig(data, _defaultTheme)
    }

    function updateWallpaper(updates) {
        wallpaper = Object.assign({}, wallpaper, updates || {})
        _scheduleSave()
    }

    function updateDesktopModule(id, updates) {
        if (!id || !updates || typeof updates !== "object")
            return

        let changed = false
        desktopModules = desktopModules.map(function(module) {
            if (!module || module.id !== id)
                return module
            changed = true
            return Object.assign({}, module, updates)
        })

        if (changed)
            _scheduleSave()
    }

    function namespaceFor(surface) {
        return "lunir-" + surface
    }

    Component.onCompleted: {
        _applyDefaults()
        configView.waitForJob()
        if (configView.loaded)
            _applyFromFile()
    }
}
