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
    property var task: ([])
    property var note: ([])
    property var controlCenter: ({})

    readonly property var _defaultTheme: ({
        background: "#191A21FF",
        surface: "#282A36F0",
        surfaceRaised: "#44475AE0",
        surfaceHover: "#FF79C629",
        border: "#F8F8F21F",
        borderStrong: "#FF79C661",
        text: "#F8F8F2FF",
        textMuted: "#F8F8F2B3",
        accent: "#FF79C6FF",
        track: "#F8F8F224",
        shadow: "#00000075",
        success: "#50FA7BFF",
        warning: "#FFB86CFF",
        error: "#FF5555FF",
        info: "#8BE9FDFF",
        radius: 20,
        radiusSmall: 12,
        radiusLarge: 28,
        borderWidth: 1,
        fontFamily: "Inter",
    })

    readonly property var _themeComments: ({
        background: "base background color used behind major surfaces",
        surface: "main panel/card fill color",
        surfaceRaised: "slightly brighter fill for nested cards and icon buttons",
        surfaceHover: "hover/active fill for small controls",
        border: "normal outline color for panels and popups, or #rainbow for a hue border",
        borderStrong: "stronger outline color for emphasis states",
        text: "primary readable text color",
        textMuted: "secondary labels and less prominent text",
        accent: "primary highlight color for progress, selected, and active states",
        track: "inactive progress bars, sliders, and off states",
        shadow: "dark overlay/shadow color",
        success: "positive status color",
        warning: "warning status color",
        error: "error/destructive status color",
        info: "informational status color",
        radius: "standard corner radius for panels",
        radiusSmall: "small control/card corner radius",
        radiusLarge: "large surface corner radius",
        borderWidth: "default border width in pixels",
        fontFamily: "default UI font family",
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

    readonly property var _defaultTask: ([])

    readonly property var _defaultControlCenter: ({
        marginX: 12,
        marginY: 12,
        animationStyle: "Move",
        animationTime: 180,
    })

    readonly property string _xdgConfigHome: Quickshell.env("XDG_CONFIG_HOME")
        || (Quickshell.env("HOME") + "/.config")
    readonly property string _configDir: _xdgConfigHome + "/lunir-qs"
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

    function _normalizeTaskList(value) {
        let source = value
        if (source && typeof source === "object" && !Array.isArray(source) && Array.isArray(source.tasks))
            source = source.tasks
        if (!Array.isArray(source))
            return []
        return source.filter(function(entry) {
            return typeof entry === "string"
        })
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
        task = _copy(_defaultTask)
        note = _copy(_defaultTask)
        controlCenter = _copy(_defaultControlCenter)
    }

    function _apply(parsed) {
        parsed = parsed || {}

        const legacyShell = parsed.shell && typeof parsed.shell === "object" ? parsed.shell : {}
        const legacyLauncherProps = _moduleProps(parsed, "launcher")
        const legacyTaskProps = _moduleProps(parsed, "task")
        const legacyNoteProps = _moduleProps(parsed, "note")

        theme = _merge(_defaultTheme, parsed.theme)
        wallpaper = _merge(_defaultWallpaper, parsed.wallpaper)
        weather = _merge(_defaultWeather, Object.assign({}, _moduleProps(parsed, "weather"), parsed.weather || {}))
        calendar = _merge(_defaultCalendar, Object.assign({}, _moduleProps(parsed, "calendar"), parsed.calendar || {}))
        launcher = _merge(_defaultLauncher, Object.assign({
            iconTheme: legacyShell.launcherIconTheme,
            iconThemePaths: legacyShell.launcherIconThemePaths,
        }, legacyLauncherProps, parsed.launcher || {}))
        task = _normalizeTaskList(parsed.task)
        if (task.length === 0)
            task = _normalizeTaskList(parsed.note)
        if (task.length === 0)
            task = _normalizeTaskList(legacyTaskProps)
        if (task.length === 0)
            task = _normalizeTaskList(legacyNoteProps)
        note = task
        controlCenter = _merge(_defaultControlCenter, parsed.controlCenter)
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
        _assign(data, "task", task, _defaultTask)
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
        _assign(data, "task", task, _defaultTask)
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

    function _themeLine(key, isLast) {
        const value = JSON.stringify(theme[key])
        const comma = isLast ? "" : ","
        return "    " + JSON.stringify(key) + ": " + value + comma + " // " + _themeComments[key]
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
        for (let i = 0; i < themeKeys.length; i++)
            lines.push(_themeLine(themeKeys[i], i === themeKeys.length - 1))
        lines.push("  }")

        const sections = ["wallpaper", "weather", "calendar", "launcher", "task", "controlCenter"].filter(function(key) {
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

    function updateTask(updates) {
        task = _normalizeTaskList(updates)
        note = task
        _scheduleSave()
    }

    function updateNote(updates) {
        updateTask(updates)
    }

    function namespaceFor(surface) {
        return "lunir-qs-" + surface
    }

    Component.onCompleted: {
        _applyDefaults()
        configView.waitForJob()
        if (configView.loaded)
            _applyFromFile()
    }
}
