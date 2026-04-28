pragma Singleton
import QtQuick 2.15
import Quickshell

Singleton {
    id: root

    function _moduleTheme(moduleConfig) {
        if (!moduleConfig || typeof moduleConfig !== "object") return null
        return moduleConfig.theme && typeof moduleConfig.theme === "object"
            ? moduleConfig.theme
            : null
    }

    function _moduleProps(moduleConfig) {
        if (!moduleConfig || typeof moduleConfig !== "object") return null
        return moduleConfig.props && typeof moduleConfig.props === "object"
            ? moduleConfig.props
            : null
    }

    function _moduleValue(moduleConfig, key) {
        const props = _moduleProps(moduleConfig)
        if (key === "textColor" || key === "accentColor" || key === "barColor") {
            if (moduleConfig && moduleConfig.color !== undefined) return moduleConfig.color
            if (props && props.color !== undefined) return props.color
        }
        if (moduleConfig && moduleConfig[key] !== undefined) return moduleConfig[key]
        if (props && props[key] !== undefined) return props[key]
        const scopedTheme = _moduleTheme(moduleConfig)
        if (scopedTheme && scopedTheme[key] !== undefined) return scopedTheme[key]
        const propsTheme = props && props.theme && typeof props.theme === "object"
            ? props.theme
            : null
        if (propsTheme && propsTheme[key] !== undefined) return propsTheme[key]
        const semanticKey = _semanticKey(key)
        if (semanticKey && Config.theme[semanticKey] !== undefined) return Config.theme[semanticKey]
        return Config.theme[key]
    }

    function _semanticKey(key) {
        switch (key) {
            case "widgetBackground": return "surface"
            case "widgetBorderColor": return "border"
            case "widgetBorderWidth": return "borderWidth"
            case "widgetBorderRadius": return "radiusSmall"
            case "textColor": return "text"
            case "accentColor": return "accent"
            case "overlayBackground": return "background"
            default: return ""
        }
    }

    function _themeValue(key, legacyKey, fallback) {
        if (Config.theme[key] !== undefined) return Config.theme[key]
        if (legacyKey && Config.theme[legacyKey] !== undefined) return Config.theme[legacyKey]
        return fallback
    }

    function _isRainbowValue(value) {
        return typeof value === "string" && /^#rainbow(?:[0-9a-fA-F]{2})?$/i.test(value)
    }

    function _rainbowAlpha(value) {
        if (!_isRainbowValue(value)) return 1.0
        return value.length === 10 ? parseInt(value.slice(8, 10), 16) / 255 : 1.0
    }

    function _colorComponent(value) {
        if (typeof value !== "string") return parseFloat(value) / 255
        const trimmed = value.trim()
        const isPercent = trimmed.endsWith("%")
        const parsed = parseFloat(trimmed)
        return isPercent ? parsed / 100 : parsed / 255
    }

    function _alphaComponent(value) {
        if (value === undefined || value === null || value === "") return 1.0
        if (typeof value !== "string") return parseFloat(value)
        const trimmed = value.trim()
        const isPercent = trimmed.endsWith("%")
        const parsed = parseFloat(trimmed)
        return isPercent ? parsed / 100 : parsed
    }

    // Parse "#RRGGBBAA", "#RRGGBB", rgb(...), or rgba(...) strings into Qt color values.
    function _c(str, fallback) {
        if (!str) return Qt.color(fallback)
        if (typeof str !== "string") return str
        if (_isRainbowValue(str)) return Qt.rgba(0, 0, 0, 0)
        const hex = str.match(/^#([0-9a-fA-F]{6})([0-9a-fA-F]{2})?$/)
        if (hex) {
            const rgb = hex[1]
            const alpha = hex[2] || "ff"
            return Qt.rgba(
                parseInt(rgb.slice(0, 2), 16) / 255,
                parseInt(rgb.slice(2, 4), 16) / 255,
                parseInt(rgb.slice(4, 6), 16) / 255,
                parseInt(alpha, 16) / 255
            )
        }
        const rgb = str.match(/^rgba?\(\s*(.*?)\s*\)$/i)
        if (rgb) {
            const parts = rgb[1].replace(/\s*\/\s*/, " / ").trim().split(/\s*,\s*|\s+/).filter(Boolean)
            const slashIndex = parts.indexOf("/")
            const alphaIndex = slashIndex >= 0 ? slashIndex + 1 : 3
            if (parts.length >= 3) {
                return Qt.rgba(
                    _colorComponent(parts[0]),
                    _colorComponent(parts[1]),
                    _colorComponent(parts[2]),
                    _alphaComponent(parts[alphaIndex])
                )
            }
        }
        return Qt.color(str)
    }

    function color(moduleConfig, key, fallback) {
        return _c(_moduleValue(moduleConfig, key), fallback)
    }

    function value(moduleConfig, key, fallback) {
        const raw = _moduleValue(moduleConfig, key)
        return raw !== undefined ? raw : fallback
    }

    function isRainbowBorder(moduleConfig) {
        return _isRainbowValue(_moduleValue(moduleConfig, "widgetBorderColor"))
    }

    function isRainbow(moduleConfig, key) {
        return _isRainbowValue(_moduleValue(moduleConfig, key))
    }

    function rainbowAlpha(moduleConfig, key) {
        return _rainbowAlpha(_moduleValue(moduleConfig, key))
    }

    function rainbowColorFromHue(hue, alpha) {
        const h = ((hue % 360) + 360) % 360
        const hp = h / 60
        const hi = Math.floor(hp)
        const c = 0.78
        const m = 0.22
        const xv = c * (1 - Math.abs((hp % 2) - 1))
        let r = m
        let g = m
        let b = m
        if (hi === 0) { r += c; g += xv }
        else if (hi === 1) { r += xv; g += c }
        else if (hi === 2) { g += c; b += xv }
        else if (hi === 3) { g += xv; b += c }
        else if (hi === 4) { r += xv; b += c }
        else { r += c; b += xv }
        return Qt.rgba(r, g, b, alpha === undefined ? 1.0 : alpha)
    }

    function positionalRainbowColor(moduleConfig, alpha) {
        const x = Number(moduleConfig && moduleConfig.x !== undefined ? moduleConfig.x : 0)
        const width = Number(moduleConfig && moduleConfig.width !== undefined ? moduleConfig.width : 0)
        const centerX = x + width / 2
        const referenceWidth = 2560
        const frac = ((centerX % referenceWidth) + referenceWidth) % referenceWidth / referenceWidth
        return rainbowColorFromHue(120 + frac * 300, alpha)
    }

    function positionalRainbowSample(moduleConfig, localFrac, alpha) {
        const x = Number(moduleConfig && moduleConfig.x !== undefined ? moduleConfig.x : 0)
        const width = Number(moduleConfig && moduleConfig.width !== undefined ? moduleConfig.width : 0)
        const referenceWidth = 2560
        const absoluteX = x + width * Math.max(0, Math.min(1, localFrac))
        const frac = ((absoluteX % referenceWidth) + referenceWidth) % referenceWidth / referenceWidth
        return rainbowColorFromHue(120 + frac * 300, alpha)
    }

    readonly property bool borderIsRainbow: _isRainbowValue(_themeValue("border", "widgetBorderColor", "#F8F8F21F"))

    function parse(colorString, fallback) {
        return _c(colorString, fallback || "#000000FF")
    }

    function number(moduleConfig, key, fallback) {
        const value = _moduleValue(moduleConfig, key)
        return value !== undefined ? value : fallback
    }

    function alpha(color, amount) {
        return Qt.rgba(color.r, color.g, color.b, amount)
    }

    readonly property color background:    _c(_themeValue("background", "overlayBackground", "#191A21FF"), "#191A21FF")
    readonly property color surface:       _c(_themeValue("surface", "widgetBackground", "#282A36F0"), "#282A36F0")
    readonly property color border:        _c(_themeValue("border", "widgetBorderColor", "#F8F8F21F"), "#F8F8F21F")
    readonly property color text:          _c(_themeValue("text", "textColor", "#F8F8F2FF"), "#F8F8F2FF")
    readonly property color textMuted:     _c(_themeValue("textMuted", "", "#F8F8F2B3"), "#F8F8F2B3")
    readonly property color accent:        _c(_themeValue("accent", "accentColor", "#FF79C6FF"), "#FF79C6FF")
    readonly property color track:         _c(_themeValue("track", "", "#F8F8F224"), "#F8F8F224")

    readonly property real radiusSmall:     _themeValue("radiusSmall", "", 12)
    readonly property real radiusLarge:     _themeValue("radiusLarge", "", 28)
    readonly property real borderWidth:     _themeValue("borderWidth", "widgetBorderWidth", 1)
    readonly property string fontFamily:    Config.theme.fontFamily || "Inter"

}
