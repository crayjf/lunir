pragma Singleton
import QtQuick 2.15
import Quickshell
import Quickshell.Io

Singleton {
    id: root

    property var theme: ({})
    property var wallpaper: ({})
    property var weather: ({})
    property var calendar: ({})
    property var launcher: ({})
    property var garmin: ({})
    property var desktopModules: ([])
    property var controlCenter: ({})
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
            x: 940,
            y: 20,
            width: 660,
            height: 110,
            widgetBackground: "#00000000",
        },
        {
            id: "desktop-dateday",
            type: "dateday",
            x: 940,
            y: 135,
            height: 40,
            widgetBackground: "#00000000",
        },
        {
            id: "desktop-datemonth",
            type: "datemonth",
            x: 1000,
            y: 135,
            height: 40,
            widgetBackground: "#00000000",
        },
        {
            id: "desktop-clock",
            type: "clock",
            x: 940,
            y: 180,
            width: 200,
            height: 200,
            widgetBackground: "#00000000",
        },
        {
            id: "desktop-progress",
            type: "progress",
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
            height: 220,
            minHeight: 120,
            spanMonitorWidth: true,
            stickToBottom: true,
            maxHeightRatio: 0.25,
            widgetBackground: "#00000000",
        },
    ])

    readonly property var _defaultControlCenter: ({
        marginX: 12,
        marginY: 12,
        animationStyle: "Move",
        animationTime: 180,
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
        return JSON.parse(JSON.stringify(value))
    }

    function _merge(defaults, value) {
        const cleaned = {}
        const input = value || {}
        for (const key of Object.keys(input)) {
            if (input[key] !== undefined)
                cleaned[key] = input[key]
        }
        return Object.assign(root._copy(defaults), cleaned)
    }

    function _normalizeDesktopModules(value) {
        const defaults = _copy(_defaultDesktopModules)
        if (value === undefined)
            return defaults
        if (!Array.isArray(value))
            return defaults

        const source = _migrateLegacyDesktopModules(value)
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

    function _migrateLegacyDesktopModules(value) {
        const modules = _copy(value)
        const legacyIndex = modules.findIndex(function(module) {
            return module && module.id === "desktop-clock" && module.type === "clock"
        })
        const hasSplitModules = modules.some(function(module) {
            return module && typeof module.id === "string" && (
                module.id.indexOf("desktop-clock-") === 0 ||
                module.id.indexOf("desktop-") === 0 && ["desktop-weekday", "desktop-dateday", "desktop-datemonth", "desktop-clock", "desktop-progress"].indexOf(module.id) >= 0
            )
        })

        if (legacyIndex >= 0 && !hasSplitModules) {
            const legacy = modules[legacyIndex]
            const x = legacy.x ?? 940
            const y = legacy.y ?? 20
            const width = legacy.width ?? 660
            const height = legacy.height ?? 280
            const background = legacy.widgetBackground ?? "#00000000"
            const color = legacy.color

            modules.splice(legacyIndex, 1,
                {
                    id: "desktop-weekday",
                    type: "weekday",
                    x: x,
                    y: y,
                    width: width,
                    height: Math.max(90, Math.round(height * 0.42)),
                    widgetBackground: background,
                    color: color,
                },
                {
                    id: "desktop-dateday",
                    type: "dateday",
                    x: x,
                    y: y + Math.max(90, Math.round(height * 0.42)),
                    height: 36,
                    widgetBackground: background,
                    color: color,
                },
                {
                    id: "desktop-datemonth",
                    type: "datemonth",
                    x: x + 60,
                    y: y + Math.max(90, Math.round(height * 0.42)),
                    height: 36,
                    widgetBackground: background,
                    color: color,
                },
                {
                    id: "desktop-clock",
                    type: "clock",
                    x: x,
                    y: y + Math.max(126, Math.round(height * 0.42) + 36),
                    width: 200,
                    height: 200,
                    widgetBackground: background,
                    color: color,
                },
                {
                    id: "desktop-progress",
                    type: "progress",
                    x: x,
                    y: y + Math.max(170, height - 24),
                    width: width,
                    height: 24,
                    minHeight: 6,
                    widgetBackground: background,
                    color: color,
                }
            )
        }

        for (let i = 0; i < modules.length; i++) {
            const module = modules[i]
            if (!module || typeof module !== "object")
                continue
            if (module.id === "desktop-clock-weekday") {
                modules[i] = Object.assign({}, module, { id: "desktop-weekday", type: "weekday" })
            } else if (module.id === "desktop-clock-date") {
                modules[i] = Object.assign({}, module, { id: "desktop-dateday", type: "dateday" })
            } else if (module.id === "desktop-clock-time" || (module.id === "desktop-time" && module.type === "time")) {
                modules[i] = Object.assign({}, module, { id: "desktop-clock", type: "clock", width: 200, height: 200 })
            } else if (module.id === "desktop-clock-progress") {
                modules[i] = Object.assign({}, module, { id: "desktop-progress", type: "progress" })
            } else if (module.type === "clockWeekday") {
                modules[i] = Object.assign({}, module, { type: "weekday" })
            } else if (module.type === "clockDate") {
                modules[i] = Object.assign({}, module, { type: "dateday" })
            } else if (module.id === "desktop-date" || module.type === "date") {
                modules[i] = Object.assign({}, module, { id: "desktop-dateday", type: "dateday" })
                if (!modules.some(function(m) { return m && m.id === "desktop-datemonth" }))
                    modules.splice(i + 1, 0, { id: "desktop-datemonth", type: "datemonth", x: (module.x ?? 0) + 60, y: module.y ?? 0, height: module.height ?? 40, widgetBackground: module.widgetBackground ?? "#00000000", color: module.color })
            } else if (module.type === "clockTime") {
                modules[i] = Object.assign({}, module, { type: "clock" })
            } else if (module.type === "clockProgress") {
                modules[i] = Object.assign({}, module, { type: "progress" })
            }
        }

        return modules
    }

    function _moduleProps(parsed, type) {
        if (!parsed || !Array.isArray(parsed.modules)) return {}
        const mod = parsed.modules.find(function(m) {
            return m && m.type === type && m.props && typeof m.props === "object"
        })
        return mod ? mod.props : {}
    }

    function _applyDefaults() {
        theme = _copy(_defaultTheme)
        wallpaper = _copy(_defaultWallpaper)
        weather = _copy(_defaultWeather)
        calendar = _copy(_defaultCalendar)
        launcher = _copy(_defaultLauncher)
        desktopModules = _copy(_defaultDesktopModules)
        garmin = _copy(_defaultGarmin)
        controlCenter = _copy(_defaultControlCenter)
        cava = _copy(_defaultCava)
    }

    function _apply(parsed) {
        parsed = parsed || {}

        const legacyShell = parsed.shell && typeof parsed.shell === "object" ? parsed.shell : {}
        const legacyLauncherProps = _moduleProps(parsed, "launcher")

        theme = _merge(_defaultTheme, parsed.theme)
        wallpaper = _merge(_defaultWallpaper, parsed.wallpaper)
        weather = _merge(_defaultWeather, Object.assign({}, _moduleProps(parsed, "weather"), parsed.weather || {}))
        calendar = _merge(_defaultCalendar, Object.assign({}, _moduleProps(parsed, "calendar"), parsed.calendar || {}))
        launcher = _merge(_defaultLauncher, Object.assign({
            iconTheme: legacyShell.launcherIconTheme,
            iconThemePaths: legacyShell.launcherIconThemePaths,
        }, legacyLauncherProps, parsed.launcher || {}))
        desktopModules = _normalizeDesktopModules(parsed.desktopModules)
        garmin = _merge(_defaultGarmin, parsed.garmin)
        controlCenter = _merge(_defaultControlCenter, parsed.controlCenter)
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
        let out = ""
        let inString = false
        let escaped = false
        for (let i = 0; i < text.length; i++) {
            const ch = text[i]
            const next = i + 1 < text.length ? text[i + 1] : ""

            if (!inString && ch === "/" && next === "/") {
                while (i < text.length && text[i] !== "\n")
                    i++
                if (i < text.length)
                    out += "\n"
                continue
            }

            out += ch

            if (escaped) {
                escaped = false
            } else if (ch === "\\") {
                escaped = true
            } else if (ch === "\"") {
                inString = !inString
            }
        }
        return out
    }

    function _compact(value, defaults) {
        if (!value || typeof value !== "object" || Array.isArray(value))
            return JSON.stringify(value) === JSON.stringify(defaults) ? undefined : value

        const out = {}
        for (const key of Object.keys(value)) {
            const compactValue = _compact(value[key], defaults ? defaults[key] : undefined)
            if (compactValue !== undefined)
                out[key] = compactValue
        }
        return Object.keys(out).length > 0 ? out : undefined
    }

    function _assign(data, key, value, defaults) {
        const compactValue = _compact(value, defaults)
        if (compactValue !== undefined)
            data[key] = compactValue
    }

    function _scheduleSave() {
        _saveTimer.restart()
    }

    function saveImmediate() {
        _saveTimer.stop()
        const data = { version: 3 }
        data.theme = theme
        _assign(data, "wallpaper", wallpaper, _defaultWallpaper)
        _assign(data, "weather", weather, _defaultWeather)
        _assign(data, "calendar", calendar, _defaultCalendar)
        _assign(data, "launcher", launcher, _defaultLauncher)
        _assign(data, "desktopModules", desktopModules, _defaultDesktopModules)
        _assign(data, "garmin", garmin, _defaultGarmin)
        _assign(data, "cava", cava, _defaultCava)
        data.controlCenter = controlCenter
        configView.setText(_stringifyConfig(data))
    }

    function _save() {
        const data = { version: 3 }
        data.theme = theme
        _assign(data, "wallpaper", wallpaper, _defaultWallpaper)
        _assign(data, "weather", weather, _defaultWeather)
        _assign(data, "calendar", calendar, _defaultCalendar)
        _assign(data, "launcher", launcher, _defaultLauncher)
        _assign(data, "desktopModules", desktopModules, _defaultDesktopModules)
        _assign(data, "garmin", garmin, _defaultGarmin)
        _assign(data, "cava", cava, _defaultCava)
        data.controlCenter = controlCenter

        _pendingData = data
        _mkdirProc.running = true
    }

    function _indent(text, spaces) {
        const pad = " ".repeat(spaces)
        return text.split("\n").map(function(line) {
            return line.length > 0 ? pad + line : line
        }).join("\n")
    }

    function _appendSection(lines, key, value, isLast) {
        const indented = _indent(JSON.stringify(value, null, 2), 2)
        lines.push("  " + JSON.stringify(key) + ": " + indented.substring(2) + (isLast ? "" : ","))
    }

    function _stringifyConfig(data) {
        const lines = [
            "{",
            "  \"version\": " + data.version + ",",
            "  \"theme\": {",
        ]

        const themeKeys = Object.keys(_defaultTheme)
        for (let i = 0; i < themeKeys.length; i++) {
            const key = themeKeys[i]
            const comma = i === themeKeys.length - 1 ? "" : ","
            lines.push("    " + JSON.stringify(key) + ": " + JSON.stringify(theme[key]) + comma)
        }
        lines.push("  }")

        const sections = ["wallpaper", "weather", "calendar", "launcher", "desktopModules", "garmin", "cava", "controlCenter"].filter(function(key) {
            return data[key] !== undefined
        })
        if (sections.length > 0)
            lines[lines.length - 1] += ","
        for (let i = 0; i < sections.length; i++) {
            _appendSection(lines, sections[i], data[sections[i]], i === sections.length - 1)
        }

        lines.push("}")
        return lines.join("\n") + "\n"
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
