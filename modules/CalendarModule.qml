import QtQuick 2.15
import Quickshell.Io 0.1
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    readonly property var _cfg:        moduleConfig ? (moduleConfig.props || {}) : {}
    readonly property var _sources:    _cfg.calendars     || []
    readonly property bool _showColors: _cfg.showColors !== false
    readonly property int _refreshMins: _cfg.refreshInterval || 30

    property var _events:    []
    property int _viewYear:  new Date().getFullYear()
    property int _viewMonth: new Date().getMonth()
    property var _cells:     []

    readonly property var _MONTHS: ["JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE",
                                     "JULY","AUGUST","SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"]
    readonly property var _DOW:    ["MON","TUE","WED","THU","FRI","SAT","SUN"]
    readonly property var _GCAL:   ({
        "tomato":"#d50000","flamingo":"#e67c73","tangerine":"#f4511e","banana":"#f6bf26",
        "sage":"#33b679","basil":"#0b8043","peacock":"#039be5","blueberry":"#3f51b5",
        "lavender":"#7986cb","grape":"#8e24aa","graphite":"#616161"
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

    function _buildFetchCmd() {
        if (!_sources || _sources.length === 0) return ""
        const parts = []
        for (const src of _sources) {
            const color = src.color || "#7986cb"
            parts.push("printf '%s\\n' '---SEP:" + color + "---'")
            parts.push("curl -sL --max-time 15 '" + src.url.replace(/'/g, "'\\''") + "'")
        }
        return parts.join("; ")
    }

    function _fetchAll() {
        const cmd = _buildFetchCmd()
        if (!cmd) { root._buildGrid(); return }
        fetchProc._cmd = cmd
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
        const unfolded = text.replace(/\r?\n[ \t]/g,"")
        const lines = unfolded.split(/\r?\n/)
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
        const chunks = raw.split(/^---SEP:(#[0-9a-fA-F]{6})---$/m)
        for (let i = 1; i+1 < chunks.length; i += 2)
            allEvents.push(..._parseICS(chunks[i+1], chunks[i].trim()))
        root._events = allEvents
        root._buildGrid()
    }

    // ── Grid builder ──────────────────────────────────────────────────────────
    function _buildGrid() {
        const today    = new Date()
        const firstDow = (new Date(_viewYear, _viewMonth, 1).getDay() + 6) % 7
        const dim      = new Date(_viewYear, _viewMonth+1, 0).getDate()
        const mStart   = new Date(_viewYear, _viewMonth, 1)
        const mEnd     = new Date(_viewYear, _viewMonth+1, 0, 23, 59, 59)
        const sel      = SelectedDay.selectedDay

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

    Connections {
        target: SelectedDay
        function onDayChanged() { root._buildGrid() }
    }

    Timer {
        interval: _refreshMins * 60000; repeat: true
        running: root.visible; triggeredOnStart: true
        onTriggered: root._fetchAll()
    }

    WheelHandler {
        target: null
        onWheel: (event) => {
            if (event.angleDelta.y < 0) {
                root._viewMonth++
                if (root._viewMonth > 11) { root._viewMonth = 0; root._viewYear++ }
            } else {
                root._viewMonth--
                if (root._viewMonth < 0) { root._viewMonth = 11; root._viewYear-- }
            }
            root._buildGrid()
        }
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors { fill: parent; margins: 8 }
        spacing: 5

        Text {
            text: root._MONTHS[root._viewMonth] + "  " + root._viewYear
            font.pixelSize: 11; font.letterSpacing: 2
            color: Theme.textColor
            anchors.horizontalCenter: parent.horizontalCenter
        }

        // DOW headers
        Row {
            width: parent.width
            Repeater {
                model: root._DOW
                delegate: Text {
                    width: parent.width / 7
                    text: modelData; font.pixelSize: 9; font.letterSpacing: 1
                    color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.45)
                    horizontalAlignment: Text.AlignHCenter
                }
            }
        }

        // Calendar grid
        Grid {
            id: calGrid
            columns: 7
            width: parent.width
            rowSpacing: 2; columnSpacing: 0

            Repeater {
                model: root._cells
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    property var cell: modelData

                    width:  calGrid.width / 7
                    height: 64
                    color: cell.isSel ? Qt.rgba(Theme.accentColor.r,Theme.accentColor.g,Theme.accentColor.b,0.25)
                         : cell.isToday ? Qt.rgba(1,1,1,0.08) : "transparent"
                    radius: 3

                    Column {
                        anchors { fill: parent; margins: 3 }
                        spacing: 2
                        visible: cell.day > 0

                        Text {
                            text: cell.day
                            font.pixelSize: 10
                            font.bold: cell.isToday
                            color: cell.isToday ? Theme.accentColor : Theme.textColor
                        }

                        Repeater {
                            model: cell.events
                            delegate: Rectangle {
                                required property var modelData
                                width: parent.width - 2; height: 13; radius: 2
                                color: root._showColors ? modelData.color : Qt.rgba(1,1,1,0.4)
                                clip: true
                                Text {
                                    anchors { fill: parent; leftMargin: 3 }
                                    text: modelData.summary
                                    font.pixelSize: 11; color: "white"
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: cell.day > 0
                        onClicked: SelectedDay.setSelectedDay(new Date(root._viewYear, root._viewMonth, cell.day))
                    }
                }
            }
        }
    }
}
