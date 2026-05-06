pragma Singleton
import QtQuick 2.15
import Quickshell

Singleton {
    readonly property var _moduleFiles: ({
        clock: "ClockModule.qml",
        weekday: "WeekdayModule.qml",
        dateday: "DateDayModule.qml",
        datemonth: "DateMonthModule.qml",
        time: "TimeModule.qml",
        progress: "ProgressModule.qml",
        calendar: "CalendarModule.qml",
        today: "CalendarModule.qml",
        weather: "WeatherModule.qml",
        media: "MediaModule.qml",
        cava: "CavaModule.qml",
        notifications: "NotificationsModule.qml",
        audio: "AudioModule.qml",
        system: "SystemModule.qml",
        wallpaper: "WallpaperModule.qml",
        quote: "QuoteModule.qml",
        garmin: "GarminModule.qml",
    })

    readonly property var desktopModules: (!Config.desktopWidgetsEnabled ? [] : (Config.desktopModules || [])).filter(function(module) {
        return !!module && typeof module === "object" && module.enabled !== false
    }).map(function(module) {
        if (!module || typeof module !== "object")
            return module

        const merged = Object.assign({}, module)
        if (merged.type === "cava") {
            if (merged.height === undefined)
                merged.height = Config.cava.height || 220
            merged.props = Object.assign({}, Config.cava)
            if (merged.color !== undefined)
                merged.props.barColor = merged.color
        }
        return merged
    })

    function url(type) {
        const file = _moduleFiles[type]
        return file ? Qt.resolvedUrl("../modules/" + file) : ""
    }

    function panelConfig(type, extraProps) {
        const props = Object.assign({}, settingsFor(type), extraProps || {}, { nativePanel: true })
        return { id: type, type: type, props: props }
    }

    function settingsFor(type) {
        switch (type) {
            case "weather": return Config.weather
            case "calendar":
            case "today": return Config.calendar
            case "launcher": return Config.launcher
            case "garmin": return Config.garmin
            case "cava": return Config.cava
            default: return {}
        }
    }
}
