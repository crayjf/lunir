import QtQuick 2.15
import Quickshell.Io 0.1
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    readonly property var _cfg: moduleConfig ? (moduleConfig.props || {}) : {}
    readonly property string apiKey:   _cfg.apiKey   || ""
    readonly property string location: _cfg.location || "Berlin,DE"
    readonly property string units:    _cfg.units    || "metric"
    readonly property int refreshMins: _cfg.refreshInterval || 30

    readonly property string tempUnit:  units === "metric" ? "°C" : "°F"

    readonly property var _ICONS: ({
        "01":"☀","02":"🌤","03":"⛅","04":"☁","09":"🌧","10":"🌦","11":"⛈","13":"🌨","50":"🌫"
    })
    readonly property var _DAYS: ["SUN","MON","TUE","WED","THU","FRI","SAT"]
    readonly property var _SLOTS: [
        { label:"MORN",hour:6 },{ label:"NOON",hour:12 },{ label:"AFTN",hour:15 },
        { label:"EVNG",hour:18 },{ label:"NIGHT",hour:21 }
    ]

    function _owmIcon(code) {
        return _ICONS[code.substring(0,2)] || "·"
    }

    // ── State ─────────────────────────────────────────────────────────────────
    property string cityText: location.toUpperCase()
    property string condText: "LOADING"
    property string condIconText: ""
    property string tempText: "—" + tempUnit
    property string hlText: "↑—° ↓—°"

    property var intradayData: [
        {label:"MORN",icon:"·",val:"—"},{label:"NOON",icon:"·",val:"—"},
        {label:"AFTN",icon:"·",val:"—"},{label:"EVNG",icon:"·",val:"—"},
        {label:"NIGHT",icon:"·",val:"—"}
    ]
    property var forecastData: [
        {label:"·",icon:"·",val:"—"},{label:"·",icon:"·",val:"—"},{label:"·",icon:"·",val:"—"},
        {label:"·",icon:"·",val:"—"},{label:"·",icon:"·",val:"—"}
    ]

    // ── Fetch ─────────────────────────────────────────────────────────────────
    property bool _curDone: false
    property bool _fcDone:  false
    property var  _curData: null
    property var  _fcData:  null

    Process {
        id: curProc
        command: ["curl", "-sL", "--max-time", "10",
            "https://api.openweathermap.org/data/2.5/weather?q=" +
            encodeURIComponent(root.location) + "&appid=" + root.apiKey + "&units=" + root.units]
        running: false
        stdout: StdioCollector { id: curStdio }
        onExited: {
            try { root._curData = JSON.parse(curStdio.text) } catch(_) {}
            root._curDone = true
            root._tryRender()
        }
    }

    Process {
        id: fcProc
        command: ["curl", "-sL", "--max-time", "10",
            "https://api.openweathermap.org/data/2.5/forecast?q=" +
            encodeURIComponent(root.location) + "&appid=" + root.apiKey + "&units=" + root.units]
        running: false
        stdout: StdioCollector { id: fcStdio }
        onExited: {
            try { root._fcData = JSON.parse(fcStdio.text) } catch(_) {}
            root._fcDone = true
            root._tryRender()
        }
    }

    function _fetchAll() {
        if (!apiKey) { condText = "NO API KEY"; return }
        _curDone = false; _fcDone = false
        _curData = null; _fcData = null
        curProc.running = true
        fcProc.running  = true
    }

    function _tryRender() {
        if (!_curDone || !_fcDone) return
        const cur = _curData; const fc = _fcData
        if (!cur || !cur.main) { condText = cur?.message || "ERROR"; return }

        const main = cur.main; const wx = cur.weather[0]
        cityText     = (cur.name || location).toUpperCase()
        condText     = (wx.description || "").toUpperCase()
        condIconText = _owmIcon(wx.icon)
        tempText     = Math.round(main.temp) + tempUnit
        hlText       = "↑" + Math.round(main.temp_max) + "° ↓" + Math.round(main.temp_min) + "°"

        if (!fc || !fc.list) return
        const list = fc.list; const today = new Date()

        // Intraday
        const intra = [...intradayData]
        for (let i = 0; i < _SLOTS.length; i++) {
            const { label, hour } = _SLOTS[i]
            let best = null; let bestDiff = Infinity
            for (const e of list) {
                const d = new Date(e.dt * 1000)
                const sameDay = d.getFullYear() === today.getFullYear() &&
                                d.getMonth() === today.getMonth() &&
                                d.getDate() === today.getDate()
                if (!sameDay) continue
                const diff = Math.abs(d.getHours() - hour)
                if (diff < bestDiff) { bestDiff = diff; best = e }
            }
            intra[i] = { label, icon: best && bestDiff <= 2 ? _owmIcon(best.weather[0].icon) : "·",
                         val: best && bestDiff <= 2 ? Math.round(best.main.temp) + tempUnit : "—" }
        }
        intradayData = intra

        // 5-day forecast
        const buckets = {}
        for (const e of list) {
            const d = new Date(e.dt * 1000)
            const key = d.getFullYear() + "-" + d.getMonth() + "-" + d.getDate()
            if (!buckets[key]) buckets[key] = { tMin: e.main.temp_min, tMax: e.main.temp_max, icon: e.weather[0].icon, date: d }
            else {
                buckets[key].tMin = Math.min(buckets[key].tMin, e.main.temp_min)
                buckets[key].tMax = Math.max(buckets[key].tMax, e.main.temp_max)
                if (d.getHours() >= 11 && d.getHours() <= 14) buckets[key].icon = e.weather[0].icon
            }
        }
        const days = Object.values(buckets).slice(0, 5)
        const fc5 = [...forecastData]
        for (let i = 0; i < days.length; i++) {
            const b = days[i]
            const isToday = b.date.getFullYear() === today.getFullYear() &&
                            b.date.getMonth() === today.getMonth() &&
                            b.date.getDate() === today.getDate()
            fc5[i] = { label: isToday ? "TODAY" : _DAYS[b.date.getDay()],
                       icon: _owmIcon(b.icon),
                       val: Math.round(b.tMax) + "° / " + Math.round(b.tMin) + "°" }
        }
        forecastData = fc5
    }

    Timer {
        interval: refreshMins * 60000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._fetchAll()
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors { fill: parent; margins: 10 }
        spacing: 10

        // Line 1: current
        Row {
            spacing: 14
            Text { text: root.cityText;     font.pixelSize: 12; font.letterSpacing: 2; color: Theme.textColor }
            Text { text: "·";               font.pixelSize: 12; color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.4) }
            Text { text: root.condText;     font.pixelSize: 11; color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.7) }
            Text { text: root.condIconText; font.pixelSize: 16 }
            Text { text: root.tempText;     font.pixelSize: 14; color: Theme.textColor }
            Text { text: root.hlText;       font.pixelSize: 10; color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.6) }
        }

        // Line 2: intraday slots
        Row {
            width: parent.width
            Repeater {
                model: root.intradayData
                delegate: Column {
                    width: parent.width / 5
                    spacing: 3
                    Text { text: modelData.label; font.pixelSize: 9; color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.5); anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: modelData.icon;  font.pixelSize: 16; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: modelData.val;   font.pixelSize: 10; color: Theme.textColor; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
        }

        // Separator
        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }

        // Line 3: 5-day forecast
        Row {
            width: parent.width
            Repeater {
                model: root.forecastData
                delegate: Column {
                    width: parent.width / 5
                    spacing: 3
                    Text { text: modelData.label; font.pixelSize: 9; color: Theme.accentColor; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: modelData.icon;  font.pixelSize: 16; anchors.horizontalCenter: parent.horizontalCenter }
                    Text { text: modelData.val;   font.pixelSize: 10; color: Theme.textColor; anchors.horizontalCenter: parent.horizontalCenter }
                }
            }
        }
    }
}
