import QtQuick 2.15
import Quickshell.Io 0.1
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    readonly property var _cfg:        moduleConfig ? (moduleConfig.props || {}) : {}
    readonly property var _sources:    _cfg.calendars     || []
    readonly property bool _showColors: _cfg.showColors !== false
    readonly property int _refreshMins: _cfg.refreshInterval || 15

    property var  _events:     []
    property var  _displayDay: new Date()

    readonly property var _DAYS:   ["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"]
    readonly property var _MONTHS: ["JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE",
                                     "JULY","AUGUST","SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"]
    readonly property var _GCAL:   ({
        "tomato":"#d50000","flamingo":"#e67c73","tangerine":"#f4511e","banana":"#f6bf26",
        "sage":"#33b679","basil":"#0b8043","peacock":"#039be5","blueberry":"#3f51b5",
        "lavender":"#7986cb","grape":"#8e24aa","graphite":"#616161"
    })

    // ── Derived state ─────────────────────────────────────────────────────────
    readonly property string _headerText: {
        const d = root._displayDay
        return root._DAYS[d.getDay()] + "  ·  " + d.getDate() + " " + root._MONTHS[d.getMonth()] + " " + d.getFullYear()
    }

    readonly property var _dayEvents: {
        const d = root._displayDay
        const start = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const end   = new Date(d.getFullYear(), d.getMonth(), d.getDate(), 23, 59, 59)
        const evs = root._events.filter(function(ev) {
            if (ev.allDay) return ev.start <= end && ev.end > start
            return ev.start >= start && ev.start <= end
        })
        return evs.sort(function(a, b) { return (+b.allDay - +a.allDay) || (a.start.getTime() - b.start.getTime()) })
    }

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
        if (!_sources || _sources.length === 0) return
        const parts = []
        for (const src of _sources) {
            const color = src.color || "#7986cb"
            parts.push("printf '%s\\n' '---SEP:" + color + "---'")
            parts.push("curl -sL --max-time 15 '" + src.url.replace(/'/g, "'\\''") + "'")
        }
        fetchProc._cmd = parts.join("; ")
        fetchProc.running = true
    }

    // ── ICS parser (shared logic) ─────────────────────────────────────────────
    function _parseICSDate(v) {
        v = v.trim()
        const y = parseInt(v.substring(0,4)), mo = parseInt(v.substring(4,6))-1, d = parseInt(v.substring(6,8))
        if (v.length === 8) return new Date(y, mo, d)
        const h = parseInt(v.substring(9,11)), m = parseInt(v.substring(11,13)), s = parseInt(v.substring(13,15))||0
        return v.endsWith("Z") ? new Date(Date.UTC(y,mo,d,h,m,s)) : new Date(y,mo,d,h,m,s)
    }

    function _expandRRule(ev, rrule) {
        const until1yr = new Date(); until1yr.setFullYear(until1yr.getFullYear()+1)
        const p = {}
        for (const part of rrule.split(";")) { const eq = part.indexOf("="); if (eq>=0) p[part.substring(0,eq)]=part.substring(eq+1) }
        const freq = p["FREQ"]; if (!freq) return []
        const interval = parseInt(p["INTERVAL"]||"1"), maxCount = p["COUNT"] ? parseInt(p["COUNT"]) : 500
        const until    = p["UNTIL"] ? _parseICSDate(p["UNTIL"]) : null
        const duration = ev.end.getTime() - ev.start.getTime()
        const DNM = ["SU","MO","TU","WE","TH","FR","SA"]
        const byDay = p["BYDAY"] ? p["BYDAY"].split(",").map(function(s){return DNM.indexOf(s.replace(/[^A-Z]/g,""))}).filter(function(n){return n>=0}) : []
        const results = []; const cur = new Date(ev.start); let count = 0
        while (count < maxCount && cur <= until1yr) {
            if (until && cur > until) break
            if (freq==="WEEKLY" && byDay.length > 0) {
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
            if (line==="BEGIN:VEVENT") { inEvent=true; ev={color:defaultColor,allDay:false,rrule:""}; continue }
            if (line==="END:VEVENT")   { inEvent=false; if (ev.summary) base.push(Object.assign({},ev)); continue }
            if (!inEvent) continue
            const colon = line.indexOf(":")
            if (colon < 0) continue
            const rawKey = line.substring(0,colon).toUpperCase(), value = line.substring(colon+1)
            const baseKey = rawKey.split(";")[0], params = rawKey.includes(";") ? rawKey.substring(rawKey.indexOf(";")+1) : ""
            switch (baseKey) {
                case "SUMMARY": ev.summary = value; break
                case "DTSTART": ev.allDay=params.includes("VALUE=DATE")||value.length===8; ev.start=_parseICSDate(value); break
                case "DTEND":   ev.end=_parseICSDate(value); break
                case "RRULE":   ev.rrule=value; break
                case "COLOR":   ev.color=root._GCAL[value.toLowerCase()]||defaultColor; break
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
    }

    Connections {
        target: SelectedDay
        function onDayChanged() {
            root._displayDay = SelectedDay.selectedDay || new Date()
        }
    }

    Timer {
        interval: _refreshMins * 60000; repeat: true
        running: root.visible; triggeredOnStart: true
        onTriggered: root._fetchAll()
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors { fill: parent; margins: 10 }
        spacing: 8

        Text {
            text: root._headerText
            font.pixelSize: 10; font.letterSpacing: 2
            color: Theme.textColor
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }

        ListView {
            width: parent.width
            height: parent.height - 30
            clip: true
            model: root._dayEvents
            spacing: 0

            delegate: Row {
                width: parent.width
                height: 32
                spacing: 10

                Text {
                    width: 52
                    text: {
                        const ev = modelData
                        if (ev.allDay) return "ALL DAY"
                        const h = String(ev.start.getHours()).padStart(2,"0")
                        const m = String(ev.start.getMinutes()).padStart(2,"0")
                        return h + ":" + m
                    }
                    font.pixelSize: 10
                    color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.6)
                    verticalAlignment: Text.AlignVCenter; height: parent.height
                }

                Rectangle {
                    width: 3; height: 20; radius: 1
                    color: root._showColors ? modelData.color : Qt.rgba(1,1,1,0.4)
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    width: parent.width - 52 - 3 - 20
                    text: modelData.summary
                    font.pixelSize: 11; color: Theme.textColor
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter; height: parent.height
                }
            }

            Text {
                anchors.centerIn: parent
                visible: root._dayEvents.length === 0
                text: "NO EVENTS TODAY"
                font.pixelSize: 10; font.letterSpacing: 2
                color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.35)
            }
        }
    }
}
