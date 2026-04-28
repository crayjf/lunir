import QtQuick 2.15
import QtQuick.Controls 2.15
import Quickshell.Io
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    readonly property color _textColor:   Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property color _mutedText:   Theme.textMuted

    readonly property var _cfg:         moduleConfig ? (moduleConfig.props || {}) : {}
    readonly property var _sources:     _cfg.calendars || []
    readonly property bool _showColors: _cfg.showColors !== false
    readonly property int _refreshMins: _cfg.refreshInterval || 30

    property var _events:     []
    property int _viewYear:   new Date().getFullYear()
    property int _viewMonth:  new Date().getMonth()
    property var _cells:      []
    property var _displayDay: new Date()
    readonly property var _displayEvents: _eventsForDay(_displayDay)
    readonly property int _gridRows: Math.max(1, Math.ceil(_cells.length / 7))

    readonly property var _MONTHS: ["JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE",
                                     "JULY","AUGUST","SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"]
    readonly property var _DAYS:   ["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"]
    readonly property var _DOW:    ["MON","TUE","WED","THU","FRI","SAT","SUN"]
    readonly property var _GCAL:   ({
        "tomato":"#D50000FF","flamingo":"#E67C73FF","tangerine":"#F4511EFF","banana":"#F6BF26FF",
        "sage":"#33B679FF","basil":"#0B8043FF","peacock":"#039BE5FF","blueberry":"#3F51B5FF",
        "lavender":"#7986CBFF","grape":"#8E24AAFF","graphite":"#616161FF"
    })

    // ── ICS fetch ─────────────────────────────────────────────────────────────
    Process {
        id: fetchProc
        property string _cmd: ""
        command: ["bash", "-c", fetchProc._cmd]
        running: false
        stdout: StdioCollector { id: fetchStdio }
        onExited: root._parseAll(fetchStdio.text)
    }

    function _fetchAll() {
        if (!_sources || _sources.length === 0) { root._buildGrid(); return }
        const parts = []
        for (const src of _sources) {
            const color = src.color || "#7986CBFF"
            parts.push("printf '%s\\n' '---SEP:" + color + "---'")
            parts.push("curl -sL --max-time 15 '" + src.url.replace(/'/g, "'\\''") + "'")
        }
        fetchProc._cmd = parts.join("; ")
        fetchProc.running = true
    }

    // ── ICS parser ────────────────────────────────────────────────────────────
    function _parseICSDate(v) {
        v = v.trim()
        const y = parseInt(v.substring(0,4)), mo = parseInt(v.substring(4,6))-1, d = parseInt(v.substring(6,8))
        if (v.length === 8) return new Date(y, mo, d)
        const h = parseInt(v.substring(9,11)), m = parseInt(v.substring(11,13)), s = parseInt(v.substring(13,15)) || 0
        return v.endsWith("Z") ? new Date(Date.UTC(y,mo,d,h,m,s)) : new Date(y,mo,d,h,m,s)
    }

    function _expandRRule(ev, rrule) {
        const until1yr = new Date(); until1yr.setFullYear(until1yr.getFullYear()+1)
        const p = {}
        for (const part of rrule.split(";")) { const eq = part.indexOf("="); if (eq >= 0) p[part.substring(0,eq)] = part.substring(eq+1) }
        const freq = p["FREQ"]; if (!freq) return []
        const interval = parseInt(p["INTERVAL"]||"1"), maxCount = p["COUNT"] ? parseInt(p["COUNT"]) : 500
        const until    = p["UNTIL"] ? _parseICSDate(p["UNTIL"]) : null
        const duration = ev.end.getTime() - ev.start.getTime()
        const DNM = ["SU","MO","TU","WE","TH","FR","SA"]
        const byDay = p["BYDAY"] ? p["BYDAY"].split(",").map(function(s){return DNM.indexOf(s.replace(/[^A-Z]/g,""))}).filter(function(n){return n>=0}) : []
        const results = []; const cur = new Date(ev.start); let count = 0
        while (count < maxCount && cur <= until1yr) {
            if (until && cur > until) break
            if (freq === "WEEKLY" && byDay.length > 0) {
                const ws = new Date(cur); ws.setDate(cur.getDate()-cur.getDay())
                for (const dn of byDay) {
                    const occ = new Date(ws); occ.setDate(ws.getDate()+dn)
                    occ.setHours(ev.start.getHours(), ev.start.getMinutes(), ev.start.getSeconds())
                    if (occ >= ev.start && occ <= until1yr && (!until||occ<=until)) {
                        results.push({summary:ev.summary,color:ev.color,allDay:ev.allDay,start:new Date(occ),end:new Date(occ.getTime()+duration)})
                        if (++count >= maxCount) break
                    }
                }
            } else {
                results.push({summary:ev.summary,color:ev.color,allDay:ev.allDay,start:new Date(cur),end:new Date(cur.getTime()+duration)})
                count++
            }
            if      (freq==="DAILY")   cur.setDate(cur.getDate()+interval)
            else if (freq==="WEEKLY")  cur.setDate(cur.getDate()+7*interval)
            else if (freq==="MONTHLY") cur.setMonth(cur.getMonth()+interval)
            else if (freq==="YEARLY")  cur.setFullYear(cur.getFullYear()+interval)
            else break
        }
        return results
    }

    function _parseICS(text, defaultColor) {
        const lines = text.replace(/\r?\n[ \t]/g,"").split(/\r?\n/)
        const base = []; let inEvent = false; let ev = {}
        for (const line of lines) {
            if (line === "BEGIN:VEVENT") { inEvent = true; ev = {color:defaultColor,allDay:false,rrule:""}; continue }
            if (line === "END:VEVENT")   { inEvent = false; if (ev.summary) base.push(Object.assign({},ev)); continue }
            if (!inEvent) continue
            const colon = line.indexOf(":")
            if (colon < 0) continue
            const rawKey = line.substring(0,colon).toUpperCase(), value = line.substring(colon+1)
            const baseKey = rawKey.split(";")[0], params = rawKey.includes(";") ? rawKey.substring(rawKey.indexOf(";")+1) : ""
            switch (baseKey) {
                case "SUMMARY": ev.summary = value; break
                case "DTSTART": ev.allDay = params.includes("VALUE=DATE")||value.length===8; ev.start = _parseICSDate(value); break
                case "DTEND":   ev.end = _parseICSDate(value); break
                case "RRULE":   ev.rrule = value; break
                case "COLOR":   ev.color = root._GCAL[value.toLowerCase()] || defaultColor; break
            }
        }
        const result = []
        for (const e of base) {
            if (!e.start) continue
            if (!e.end) e.end = new Date(e.start.getTime() + (e.allDay ? 86400000 : 3600000))
            if (e.rrule) result.push(..._expandRRule(e, e.rrule))
            else result.push(e)
        }
        return result
    }

    function _parseAll(raw) {
        const allEvents = []
        const chunks = raw.split(/^---SEP:(#[0-9a-fA-F]{6}(?:[0-9a-fA-F]{2})?)---$/m)
        for (let i = 1; i+1 < chunks.length; i += 2)
            allEvents.push(..._parseICS(chunks[i+1], chunks[i].trim()))
        root._events = allEvents
        root._buildGrid()
    }

    function _eventsForDay(day) {
        if (!day) return []
        const start = new Date(day.getFullYear(), day.getMonth(), day.getDate())
        const end   = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 23, 59, 59)
        return root._events.filter(function(ev) {
            if (ev.allDay) return ev.start <= end && ev.end > start
            return ev.start >= start && ev.start <= end
        }).sort(function(a, b) {
            return (+b.allDay - +a.allDay) || (a.start.getTime() - b.start.getTime())
        })
    }

    function _eventTime(ev) {
        if (!ev) return ""
        if (ev.allDay) return "ALL DAY"
        const h = String(ev.start.getHours()).padStart(2, "0")
        const m = String(ev.start.getMinutes()).padStart(2, "0")
        return h + ":" + m
    }

    function _eventColor(ev) {
        return root._showColors && ev && ev.color
            ? Theme.parse(ev.color, "#7986CBFF")
            : Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.4)
    }

    function _sameDay(a, b) {
        return a && b &&
            a.getFullYear() === b.getFullYear() &&
            a.getMonth()    === b.getMonth()    &&
            a.getDate()     === b.getDate()
    }

    function _dayHeader() {
        return _sameDay(_displayDay, new Date()) ? "TODAY" : root._DAYS[_displayDay.getDay()]
    }

    function _setDisplayDay(day) {
        root._displayDay = day
        root._buildGrid()
    }

    function _resetDisplayDay() {
        const today = new Date()
        root._displayDay = today
        root._viewYear  = today.getFullYear()
        root._viewMonth = today.getMonth()
        root._buildGrid()
    }

    function _shiftMonth(delta) {
        root._viewMonth += delta
        while (root._viewMonth > 11) { root._viewMonth -= 12; root._viewYear++ }
        while (root._viewMonth < 0)  { root._viewMonth += 12; root._viewYear-- }
        root._buildGrid()
    }

    function _scrollMonthFromDelta(angleY, pixelY) {
        const delta = angleY !== 0 ? angleY : pixelY
        if (delta === 0) return
        root._shiftMonth(delta < 0 ? 1 : -1)
    }

    // ── Grid builder ──────────────────────────────────────────────────────────
    function _buildGrid() {
        const today    = new Date()
        const firstDow = (new Date(_viewYear, _viewMonth, 1).getDay() + 6) % 7
        const dim      = new Date(_viewYear, _viewMonth+1, 0).getDate()
        const mStart   = new Date(_viewYear, _viewMonth, 1)
        const mEnd     = new Date(_viewYear, _viewMonth+1, 0, 23, 59, 59)
        const sel      = root._displayDay

        const byDate = {}
        for (let d = 1; d <= dim; d++) byDate[d] = []
        for (const ev of _events) {
            if (ev.start > mEnd) continue
            if (ev.allDay) {
                const cur = new Date(Math.max(ev.start.getTime(), mStart.getTime()))
                while (cur < ev.end && cur <= mEnd) {
                    const d = cur.getDate()
                    if (cur.getMonth() === _viewMonth && cur.getFullYear() === _viewYear && byDate[d])
                        byDate[d].push(ev)
                    cur.setDate(d+1)
                }
            } else {
                const d = ev.start
                if (d.getFullYear()===_viewYear && d.getMonth()===_viewMonth && byDate[d.getDate()])
                    byDate[d.getDate()].push(ev)
            }
        }

        const cells = []
        for (let i = 0; i < firstDow; i++)
            cells.push({day:0, events:[], isToday:false, isSel:false})
        for (let day = 1; day <= dim; day++) {
            const isToday = today.getFullYear()===_viewYear && today.getMonth()===_viewMonth && today.getDate()===day
            const isSel   = sel && sel.getFullYear()===_viewYear && sel.getMonth()===_viewMonth && sel.getDate()===day
            cells.push({day, events:(byDate[day]||[]).slice(0,3), isToday, isSel})
        }
        while (cells.length % 7 !== 0) cells.push({day:0,events:[],isToday:false,isSel:false})
        root._cells = cells
    }

    Timer {
        interval: _refreshMins * 60000; repeat: true
        running: root.visible; triggeredOnStart: true
        onTriggered: root._fetchAll()
    }

    onVisibleChanged: if (visible) root._resetDisplayDay()
    Component.onCompleted: root._resetDisplayDay()

    // ── UI ────────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: "transparent"

        WheelHandler {
            target: null
            onWheel: (event) => root._scrollMonthFromDelta(event.angleDelta.y, event.pixelDelta.y)
        }

        Row {
            anchors { fill: parent; margins: 10 }
            spacing: 12

            // ── Left: Today / event list ──────────────────────────────────────
            Column {
                width: parent.width - parent.spacing - Math.round((parent.width - parent.spacing) * 0.6)
                height: parent.height
                spacing: 8

                Item {
                    width: parent.width
                    height: 18

                    Text {
                        anchors.centerIn: parent
                        text: root._dayHeader()
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 1.6
                        color: root._mutedText
                        horizontalAlignment: Text.AlignHCenter
                    }
                }

                ScrollView {
                    id: eventScroll
                    width: parent.width
                    height: parent.height - y
                    clip: true
                    ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                    ScrollBar.vertical.policy: root._displayEvents.length > 3 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

                    Column {
                        width: eventScroll.availableWidth
                        spacing: 6

                        Rectangle {
                            width: parent.width
                            height: 30
                            radius: 12
                            visible: root._displayEvents.length === 0
                            color: "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: "NO EVENTS"
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.letterSpacing: 1.2
                                color: root._mutedText
                            }
                        }

                        Repeater {
                            model: root._displayEvents

                            delegate: Rectangle {
                                required property var modelData
                                width: parent.width
                                height: 32
                                radius: 12
                                color: "transparent"

                                Row {
                                    anchors.fill: parent
                                    anchors.rightMargin: 8
                                    spacing: 7

                                    Rectangle {
                                        width: 3; height: 16; radius: 1.5
                                        anchors.verticalCenter: parent.verticalCenter
                                        color: root._eventColor(modelData)
                                    }

                                    Column {
                                        width: parent.width - 10
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 1

                                        Text {
                                            width: parent.width
                                            text: root._eventTime(modelData)
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 8
                                            font.letterSpacing: 1.1
                                            color: root._mutedText
                                            elide: Text.ElideRight
                                        }

                                        Text {
                                            width: parent.width
                                            text: modelData.summary
                                            font.family: Theme.fontFamily
                                            font.pixelSize: 10
                                            color: root._textColor
                                            elide: Text.ElideRight
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Right: Calendar grid ──────────────────────────────────────────
            Column {
                width: Math.round((parent.width - parent.spacing) * 0.6)
                height: parent.height
                spacing: 7

                Item {
                    width: parent.width
                    height: 18

                    Text {
                        anchors.centerIn: parent
                        text: root._MONTHS[root._viewMonth]
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 1.6
                        color: root._mutedText
                        horizontalAlignment: Text.AlignHCenter
                    }

                    Text {
                        id: yearLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 20
                        text: root._viewYear
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        color: root._textColor
                        horizontalAlignment: Text.AlignRight
                    }
                }

                Row {
                    width: parent.width
                    height: 12

                    Repeater {
                        model: root._DOW
                        delegate: Text {
                            width: parent.width / 7
                            text: modelData.substring(0, 1)
                            font.family: Theme.fontFamily
                            font.pixelSize: 8
                            color: root._mutedText
                            horizontalAlignment: Text.AlignHCenter
                        }
                    }
                }

                Grid {
                    id: calGrid
                    columns: 7
                    width: parent.width
                    height: parent.height - 44
                    rowSpacing: 3
                    columnSpacing: 3

                    Repeater {
                        model: root._cells

                        delegate: Rectangle {
                            required property var modelData
                            property var cell: modelData

                            width: (calGrid.width - calGrid.columnSpacing * 6) / 7
                            height: (calGrid.height - calGrid.rowSpacing * (root._gridRows - 1)) / root._gridRows
                            radius: 8
                            color: cell.isSel
                                ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.24)
                                : cell.isToday
                                    ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.14)
                                    : cell.events.length > 0
                                        ? "transparent"
                                        : "transparent"

                            Text {
                                anchors.centerIn: parent
                                text: cell.day > 0 ? String(cell.day) : ""
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: cell.isToday || cell.isSel
                                color: cell.isToday || cell.isSel ? root._textColor : root._mutedText
                            }

                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 3
                                spacing: 2
                                visible: cell.day > 0 && cell.events.length > 0

                                Repeater {
                                    model: Math.min(cell.events.length, 3)
                                    delegate: Rectangle {
                                        width: 3; height: 3; radius: 1.5
                                        color: root._eventColor(cell.events[index])
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: cell.day > 0
                                onClicked: root._setDisplayDay(new Date(root._viewYear, root._viewMonth, cell.day))
                                onWheel: (wheel) => root._scrollMonthFromDelta(wheel.angleDelta.y, wheel.pixelDelta.y)
                            }
                        }
                    }
                }
            }
        }
    }
}
