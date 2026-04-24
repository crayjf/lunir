import QtQuick 2.15
import Quickshell.Io
import "../lib"

Item {
    id: root

    property var moduleConfig: null

    readonly property var _cfg: moduleConfig ? (moduleConfig.props || {}) : {}
    readonly property bool _nativePanel: _cfg.nativePanel === true
    readonly property string apiKey: _cfg.apiKey || ""
    readonly property string location: _cfg.location || "Berlin,DE"
    readonly property string units: _cfg.units || "metric"
    readonly property int refreshMins: _cfg.refreshInterval || 30

    readonly property color _textColor: Theme.color(moduleConfig, "textColor", Config.theme.text)
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", Config.theme.accent)
    readonly property color _mutedText: Theme.textMuted
    readonly property color _subtleText: Theme.textMuted
    readonly property color _panelColor: Theme.surface
    readonly property color _raisedColor: Theme.surfaceRaised
    readonly property color _borderColor: Theme.border
    readonly property color _frameColor: _panelColor
    readonly property color _lineColor: Theme.alpha(_borderColor, 0.7)
    readonly property color _glassColor: _raisedColor
    readonly property color _glassBorderColor: "transparent"
    readonly property color _iconBadgeColor: Theme.alpha(_accentColor, 0.16)
    readonly property string tempUnit: units === "metric" ? "°C" : "°F"
    readonly property bool _compact: width < 360

    readonly property var _DAYS: ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]
    readonly property string _EMPTY_ICON: "○"
    readonly property var _DAY_PARTS: [
        { label: "MORN", hour: 9 },
        { label: "NOON", hour: 12 },
        { label: "AFTN", hour: 15 },
        { label: "EVE", hour: 18 },
        { label: "NIGHT", hour: 21 }
    ]
    readonly property var _OWM_ICONS: ({
        "01d": "☀",
        "01n": "☾",
        "02d": "⛅",
        "02n": "🌥",
        "03d": "🌥",
        "03n": "🌥",
        "04d": "🌥",
        "04n": "🌥",
        "09d": "🌧",
        "09n": "🌧",
        "10d": "🌦",
        "10n": "🌧",
        "11d": "⛈",
        "11n": "⛈",
        "13d": "❄",
        "13n": "❄",
        "50d": "🌫",
        "50n": "🌫"
    })
    readonly property var _CONDITION_LABELS: ({
        Thunderstorm: "Storm",
        Drizzle: "Drizzle",
        Rain: "Rain",
        Snow: "Snow",
        Mist: "Mist",
        Smoke: "Smoke",
        Haze: "Haze",
        Dust: "Dust",
        Fog: "Fog",
        Sand: "Windblown",
        Ash: "Ash",
        Squall: "Squall",
        Tornado: "Tornado",
        Clear: "Clear",
        Clouds: "Cloudy"
    })

    property string cityText: location.toUpperCase()
    property string conditionIconText: "·"
    property string tempText: "—" + tempUnit
    property string rangeText: "H —°  L —°"

    property var intradayData: [
        { label: "--", icon: "·", temp: "—" },
        { label: "--", icon: "·", temp: "—" },
        { label: "--", icon: "·", temp: "—" },
        { label: "--", icon: "·", temp: "—" },
        { label: "--", icon: "·", temp: "—" }
    ]
    property var forecastData: [
        { label: "---", icon: "·", high: "—", low: "—" },
        { label: "---", icon: "·", high: "—", low: "—" },
        { label: "---", icon: "·", high: "—", low: "—" },
        { label: "---", icon: "·", high: "—", low: "—" },
        { label: "---", icon: "·", high: "—", low: "—" }
    ]

    property bool _curDone: false
    property bool _fcDone: false
    property var _curData: null
    property var _fcData: null
    property bool _isEmptyState: false
    readonly property bool _showIntradayRow: _hasUsableIntradayData(intradayData)
    readonly property bool _showForecastRow: _hasUsableForecastData(forecastData)

    function _pad2(value) {
        const intValue = Math.max(0, value | 0)
        return intValue < 10 ? "0" + intValue : String(intValue)
    }

    function _icon(code) {
        return _OWM_ICONS[code] || _OWM_ICONS[(code || "").substring(0, 2) + "d"] || "·"
    }

    function _iconOffset(iconText, pixelSize) {
        return iconText === "🌥" ? Math.round(pixelSize * 0.16) : 0
    }

    function _temp(value) {
        return value === undefined || value === null ? "—" : Math.round(value) + "°"
    }

    function _sameDay(a, b) {
        return a.getFullYear() === b.getFullYear()
            && a.getMonth() === b.getMonth()
            && a.getDate() === b.getDate()
    }

    function _emptyHourSlot() {
        return { label: "--", icon: "·", temp: "—" }
    }

    function _blankHourSlot(label) {
        return { label: label || "", icon: "", temp: "" }
    }

    function _emptyDaySlot(index) {
        return {
            label: index < _DAYS.length ? _DAYS[(new Date().getDay() + index + 1) % _DAYS.length] : "---",
            icon: "·",
            high: "—",
            low: "—"
        }
    }

    function _hasUsableIntradayData(data) {
        return Array.isArray(data) && data.some(function(entry) {
            return entry && entry.temp && entry.temp !== "—" && entry.icon && entry.icon !== "·"
        })
    }

    function _hasUsableForecastData(data) {
        return Array.isArray(data) && data.some(function(entry) {
            return entry && entry.high && entry.high !== "—"
                && entry.low && entry.low !== "—"
                && entry.icon && entry.icon !== "·"
        })
    }

    function _setEmptyState() {
        _isEmptyState = true
        cityText = location.toUpperCase()
        conditionIconText = _EMPTY_ICON
        tempText = "—" + tempUnit
        rangeText = "H —°  L —°"
        intradayData = [_emptyHourSlot(), _emptyHourSlot(), _emptyHourSlot(), _emptyHourSlot(), _emptyHourSlot()]
        forecastData = [_emptyDaySlot(0), _emptyDaySlot(1), _emptyDaySlot(2), _emptyDaySlot(3), _emptyDaySlot(4)]
    }

    Process {
        id: curProc
        command: ["curl", "-sL", "--max-time", "10",
            "https://api.openweathermap.org/data/2.5/weather?q="
            + encodeURIComponent(root.location)
            + "&appid=" + root.apiKey
            + "&units=" + root.units]
        running: false
        stdout: StdioCollector { id: curStdio }
        onExited: {
            try { root._curData = JSON.parse(curStdio.text) } catch (_) {}
            root._curDone = true
            root._tryRender()
        }
    }

    Process {
        id: fcProc
        command: ["curl", "-sL", "--max-time", "10",
            "https://api.openweathermap.org/data/2.5/forecast?q="
            + encodeURIComponent(root.location)
            + "&appid=" + root.apiKey
            + "&units=" + root.units]
        running: false
        stdout: StdioCollector { id: fcStdio }
        onExited: {
            try { root._fcData = JSON.parse(fcStdio.text) } catch (_) {}
            root._fcDone = true
            root._tryRender()
        }
    }

    function _fetchAll() {
        if (!apiKey) {
            _setEmptyState()
            return
        }

        _curDone = false
        _fcDone = false
        _curData = null
        _fcData = null
        curProc.running = true
        fcProc.running = true
    }

    function _tryRender() {
        if (!_curDone || !_fcDone) return

        const cur = _curData
        const fc = _fcData
        if (!cur || !cur.main || !cur.weather || cur.weather.length === 0) {
            _setEmptyState()
            return
        }

        const now = new Date()
        const weather = cur.weather[0]
        _isEmptyState = false
        cityText = (cur.name || location).toUpperCase()
        conditionIconText = _icon(weather.icon || "")
        tempText = _temp(cur.main.temp) + tempUnit.replace("°", "")
        rangeText = "H " + _temp(cur.main.temp_max) + "  L " + _temp(cur.main.temp_min)

        if (!fc || !fc.list || !fc.list.length) {
            _setEmptyState()
            return
        }

        const intraday = []
        for (let i = 0; i < _DAY_PARTS.length; i++) {
            const slot = _DAY_PARTS[i]
            if (slot.hour < now.getHours()) {
                intraday.push(_blankHourSlot(slot.label))
                continue
            }
            let best = null
            let bestDiff = Infinity
            for (const entry of fc.list) {
                const entryDate = new Date(entry.dt * 1000)
                if (!_sameDay(entryDate, now) || entryDate.getTime() < now.getTime())
                    continue
                const diff = Math.abs(entryDate.getHours() - slot.hour)
                if (diff < bestDiff) {
                    best = entry
                    bestDiff = diff
                }
            }
            intraday.push(best && bestDiff <= 3
                ? {
                    label: slot.label,
                    icon: _icon(best.weather && best.weather[0] ? best.weather[0].icon : ""),
                    temp: _temp(best.main ? best.main.temp : undefined)
                }
                : _blankHourSlot(slot.label))
        }
        intradayData = intraday

        const dayBuckets = {}
        for (const entry of fc.list) {
            const entryDate = new Date(entry.dt * 1000)
            if (_sameDay(entryDate, now)) continue

            const key = entryDate.getFullYear() + "-" + entryDate.getMonth() + "-" + entryDate.getDate()
            if (!dayBuckets[key]) {
                dayBuckets[key] = {
                    date: entryDate,
                    high: entry.main.temp_max,
                    low: entry.main.temp_min,
                    icon: entry.weather && entry.weather[0] ? entry.weather[0].icon : "",
                    precip: entry.pop || 0,
                    bestHourDistance: Math.abs(entryDate.getHours() - 13)
                }
            } else {
                const bucket = dayBuckets[key]
                bucket.high = Math.max(bucket.high, entry.main.temp_max)
                bucket.low = Math.min(bucket.low, entry.main.temp_min)
                bucket.precip = Math.max(bucket.precip, entry.pop || 0)
                const distance = Math.abs(entryDate.getHours() - 13)
                if (distance < bucket.bestHourDistance) {
                    bucket.bestHourDistance = distance
                    bucket.icon = entry.weather && entry.weather[0] ? entry.weather[0].icon : bucket.icon
                }
            }
        }

        const nextDays = Object.values(dayBuckets)
            .sort(function(a, b) { return a.date.getTime() - b.date.getTime() })
            .slice(0, 5)
            .map(function(bucket) {
                return {
                    label: _DAYS[bucket.date.getDay()],
                    icon: _icon(bucket.icon),
                    high: _temp(bucket.high),
                    low: _temp(bucket.low)
                }
            })

        while (nextDays.length < 5)
            nextDays.push(_emptyDaySlot(nextDays.length))

        if (!_hasUsableIntradayData(intraday) && !_hasUsableForecastData(nextDays)) {
            _setEmptyState()
            return
        }
        forecastData = nextDays
    }

    Timer {
        interval: refreshMins * 60000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._fetchAll()
    }

    Item {
        anchors.fill: parent
        anchors.margins: root._nativePanel ? 0 : 10

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusLarge
            color: root._frameColor
            border.color: root._nativePanel ? "transparent" : root._lineColor
            border.width: root._nativePanel ? 0 : 1

            Column {
                visible: !root._isEmptyState
                anchors.fill: parent
                anchors.margins: root._compact ? 10 : 12
                spacing: 4

                Item {
                    width: parent.width
                    height: root._compact ? 14 : 24

                    Row {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.tempText
                            font.family: Theme.fontFamily
                            font.pixelSize: 16
                            font.bold: true
                            color: root._textColor
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 0
                            width: root._compact ? 30 : 34

                            Text {
                                width: parent.width
                                height: 9
                                text: root.rangeText.split("  ")[0]
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                color: root._subtleText
                                horizontalAlignment: Text.AlignLeft
                            }

                            Text {
                                width: parent.width
                                height: 9
                                text: root.rangeText.split("  ")[1] || ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                color: root._subtleText
                                horizontalAlignment: Text.AlignLeft
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.cityText
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 1.4
                        color: root._mutedText
                    }

                    Item {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: root._compact ? 34 : 40
                        height: parent.height

                        Text {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: root._iconOffset(root.conditionIconText, font.pixelSize)
                            text: root.conditionIconText
                            font.family: Theme.fontFamily
                            font.pixelSize: root._compact ? 26 : 31
                            color: root._textColor
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 0

                    Row {
                        visible: root._showIntradayRow
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: root.intradayData.slice(0, 5)

                            delegate: Item {
                                required property var modelData

                                width: (parent.width - parent.spacing * 4) / 5
                                height: root._compact ? 32 : 34

                                Column {
                                    anchors.fill: parent
                                    spacing: 0

                                    Text {
                                        width: parent.width
                                        height: 9
                                        text: modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 7
                                        font.letterSpacing: 1
                                        color: root._mutedText
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Item {
                                        width: parent.width
                                        height: parent.height - 9

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4

                                            Item {
                                                width: root._compact ? 18 : 20
                                                height: parent.height

                                                Text {
                                                    anchors.centerIn: parent
                                                    anchors.verticalCenterOffset: root._iconOffset(modelData.icon, font.pixelSize)
                                                    text: modelData.icon
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: root._compact ? 22 : 23
                                                    color: root._textColor
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                            }

                                            Column {
                                                width: root._compact ? 24 : 28
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 0

                                                Text {
                                                    width: parent.width
                                                    height: 8
                                                    text: modelData.temp
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    color: root._textColor
                                                    horizontalAlignment: Text.AlignHCenter
                                                }

                                                Text {
                                                    width: parent.width
                                                    height: 8
                                                    text: ""
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 7
                                                    color: "transparent"
                                                    horizontalAlignment: Text.AlignHCenter
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        visible: !root._showIntradayRow
                        width: parent.width
                        height: root._compact ? 32 : 34

                        Text {
                            anchors.centerIn: parent
                            text: root._EMPTY_ICON
                            font.family: Theme.fontFamily
                            font.pixelSize: root._compact ? 26 : 28
                            color: root._mutedText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 0

                    Row {
                        visible: root._showForecastRow
                        width: parent.width
                        spacing: 8

                        Repeater {
                            model: root.forecastData

                            delegate: Item {
                                required property var modelData

                                width: (parent.width - parent.spacing * 4) / 5
                                height: root._compact ? 32 : 34

                                Column {
                                    anchors.fill: parent
                                    spacing: 0

                                    Text {
                                        width: parent.width
                                        height: 9
                                        text: modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 7
                                        font.letterSpacing: 1
                                        color: root._mutedText
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Item {
                                        width: parent.width
                                        height: parent.height - 9

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4

                                            Item {
                                                width: root._compact ? 18 : 20
                                                height: parent.height

                                                Text {
                                                    anchors.centerIn: parent
                                                    anchors.verticalCenterOffset: root._iconOffset(modelData.icon, font.pixelSize)
                                                    text: modelData.icon
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: root._compact ? 22 : 23
                                                    color: root._textColor
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                            }

                                            Column {
                                                width: root._compact ? 24 : 28
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 0

                                                Text {
                                                    width: parent.width
                                                    height: 9
                                                    text: modelData.high
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    color: root._textColor
                                                    horizontalAlignment: Text.AlignHCenter
                                                }

                                                Text {
                                                    width: parent.width
                                                    height: 9
                                                    text: modelData.low
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 8
                                                    color: root._mutedText
                                                    horizontalAlignment: Text.AlignHCenter
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        visible: !root._showForecastRow
                        width: parent.width
                        height: root._compact ? 32 : 34

                        Text {
                            anchors.centerIn: parent
                            text: root._EMPTY_ICON
                            font.family: Theme.fontFamily
                            font.pixelSize: root._compact ? 26 : 28
                            color: root._mutedText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Item {
                visible: root._isEmptyState
                anchors.fill: parent

                Text {
                    anchors.centerIn: parent
                    text: root._EMPTY_ICON
                    font.family: Theme.fontFamily
                    font.pixelSize: root._compact ? 34 : 40
                    color: root._mutedText
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
