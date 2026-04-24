pragma Singleton
import QtQuick 2.15
import Quickshell

Singleton {
    readonly property var _moduleFiles: ({
        clock: "ClockModule.qml",
        calendar: "CalendarModule.qml",
        today: "CalendarModule.qml",
        weather: "WeatherModule.qml",
        media: "MediaModule.qml",
        cava: "CavaModule.qml",
        notifications: "NotificationsModule.qml",
        audio: "AudioModule.qml",
        system: "SystemModule.qml",
        task: "TaskModule.qml",
        note: "NoteModule.qml",
        wallpaper: "WallpaperModule.qml",
        quote: "QuoteModule.qml",
        garmin: "GarminModule.qml",
        empty: "EmptyModule.qml",
    })

    readonly property var desktopModules: [
        {
            id: "desktop-clock",
            type: "clock",
            x: 940,
            y: 20,
            width: 660,
            height: 280,
            widgetBackground: "#00000000",
        },
        {
            id: "desktop-quote",
            type: "quote",
            x: 960,
            y: 340,
            width: 580,
            height: 100,
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
            widgetBorderColor: "#00000000",
            widgetBorderWidth: 0,
            widgetBorderRadius: 0,
            props: { bars: 120 },
        },
    ]

    function url(type) {
        return Qt.resolvedUrl("../modules/" + (_moduleFiles[type] || _moduleFiles.empty))
    }

    function sidebarConfig(type, extraProps) {
        const props = Object.assign({}, settingsFor(type), extraProps || {}, { nativePanel: true })
        return { id: type, type: type, props: props }
    }

    function settingsFor(type) {
        switch (type) {
            case "weather": return Config.weather
            case "calendar":
            case "today": return Config.calendar
            case "launcher": return Config.launcher
            case "task": return { tasks: Config.task }
            case "note": return { tasks: Config.note }
            default: return {}
        }
    }
}
