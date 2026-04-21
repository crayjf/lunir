pragma Singleton
import QtQuick 2.15
import "./." as Lib

QtObject {
    id: root

    // Parse "rgba(r,g,b,a)" or "#hex" strings into Qt color values.
    function _c(str, fallback) {
        if (!str) return Qt.color(fallback)
        const m = str.match(/rgba?\(\s*([\d.]+)\s*,\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*([\d.]+))?\s*\)/)
        if (m) return Qt.rgba(parseFloat(m[1])/255, parseFloat(m[2])/255, parseFloat(m[3])/255,
                              m[4] !== undefined ? parseFloat(m[4]) : 1.0)
        return Qt.color(str)
    }

    readonly property bool   overlayBackgroundEnabled: Config.theme.overlayBackgroundEnabled !== false
    readonly property color  overlayBackground:  _c(Config.theme.overlayBackground,  "#00000066")
    readonly property color  widgetBackground:   _c(Config.theme.widgetBackground,   "#d91e1e2e")
    readonly property color  widgetBorderColor:  _c(Config.theme.widgetBorderColor,  "#8089b4fa")
    readonly property real   widgetBorderWidth:  Config.theme.widgetBorderWidth  !== undefined ? Config.theme.widgetBorderWidth  : 1
    readonly property real   widgetBorderRadius: Config.theme.widgetBorderRadius !== undefined ? Config.theme.widgetBorderRadius : 12
    readonly property color  textColor:          _c(Config.theme.textColor,   "#cdd6f4")
    readonly property color  accentColor:        _c(Config.theme.accentColor, "#89b4fa")
}
