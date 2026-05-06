import QtQuick 2.15
import QtQuick.Controls 2.15
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property color _mutedText: Theme.textMuted

    readonly property var _cfg: moduleConfig ? (moduleConfig.props || {}) : {}
    readonly property bool _showToday: _cfg.showToday !== false
    readonly property bool _showMonth: _cfg.showMonth !== false
    readonly property var _sources: _cfg.calendars || []
    readonly property bool _showColors: _cfg.showColors !== false
    readonly property int _refreshMins: _cfg.refreshInterval || 30
    readonly property string _calendarKey: CalendarState.requestKey(_sources)
    readonly property var _calendarState: CalendarState.states[_calendarKey] || ({
        events: [],
        signature: ""
    })

    property var _events: _calendarState.events || []
    property int _viewYear: new Date().getFullYear()
    property int _viewMonth: new Date().getMonth()
    property var _cells: []
    property var _displayDay: SelectedDay.selectedDay ? new Date(SelectedDay.selectedDay) : new Date()
    readonly property var _displayEvents: _eventsForDay(_displayDay)
    readonly property var _tomorrowDay: {
        const nextDay = new Date();
        nextDay.setDate(nextDay.getDate() + 1);
        return nextDay;
    }
    readonly property var _tomorrowEvents: _eventsForDay(_tomorrowDay)
    readonly property var _compactRowPair: _buildCompactRowPair(root._displayDay, root._tomorrowDay)
    readonly property var _compactDisplayRows: _compactRowPair.leftRows.slice(0, root._todayCompactVisibleRows)
    readonly property var _compactTomorrowRows: _compactRowPair.rightRows.slice(0, root._todayCompactVisibleRows)
    readonly property int _compactDisplayCount: Math.min(_compactRowPair.leftCount, root._todayCompactVisibleRows)
    readonly property int _compactTomorrowCount: Math.min(_compactRowPair.rightCount, root._todayCompactVisibleRows)
    readonly property int _gridRows: Math.max(1, Math.ceil(_cells.length / 7))
    readonly property int _monthPreviewCount: 5
    readonly property int _monthHeaderHeight: 10
    readonly property int _monthContentTopMargin: 1
    readonly property int _monthContentBottomMargin: 2
    readonly property int _monthContentSideMargin: 0
    readonly property int _monthContentSpacing: 2
    readonly property int _monthEventListSpacing: 0
    readonly property int _monthEventRowHeight: 13
    readonly property int _todayPanelHeight: Math.max(110, Math.min(180, 28 + root._displayEvents.length * 36))
    readonly property int _outerPadding: root._showMonth ? 10 : 0
    readonly property int _outerTopPadding: 0
    readonly property int _outerBottomPadding: root._showMonth ? 0 : root._outerPadding
    readonly property int _todayInnerMargin: root._showMonth ? 10 : 0
    readonly property int _todayCompactLeftPadding: root._showMonth ? 0 : 8
    readonly property int _todayHeaderHeight: root._showMonth ? 18 : 12
    readonly property int _todayCompactColumnGap: 12
    readonly property int _todayCompactVisibleRows: 5
    readonly property int _todayCompactRowHeight: 14
    readonly property int _todayCompactRowSpacing: 0
    readonly property int _todayCompactEmptyHeight: 30
    readonly property int _todayCompactListHeight: Math.max(
        root._todayCompactEmptyHeight,
        (root._todayCompactVisibleRows * root._todayCompactRowHeight)
            + (Math.max(0, root._todayCompactVisibleRows - 1) * root._todayCompactRowSpacing)
    )
    readonly property int _todayCompactPanelHeight: root._todayHeaderHeight + root._todayInnerSpacing + root._todayCompactListHeight
    readonly property int _monthCellHeight: root._monthContentTopMargin + root._monthHeaderHeight + root._monthContentSpacing + (root._monthPreviewCount * root._monthEventRowHeight) + (Math.max(0, root._monthPreviewCount - 1) * root._monthEventListSpacing) + root._monthContentBottomMargin
    readonly property int _monthAllDayMinRuleWidth: 0
    readonly property int _todayInnerSpacing: root._showMonth ? 8 : 4
    readonly property int preferredHeight: root._showMonth ? root._outerTopPadding + root._outerBottomPadding + (root._showToday ? root._todayPanelHeight : 0) + (root._showToday ? contentColumn.spacing : 0) + monthPanel.implicitHeight : (root._showToday ? (root._outerPadding * 2) + root._todayCompactPanelHeight : root._outerPadding * 2)
    implicitHeight: preferredHeight

    readonly property var _MONTHS: ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE", "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
    readonly property var _DAYS: ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
    readonly property var _DOW: ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    function _fetchAll() {
        CalendarState.request(_sources);
    }

    function _eventsForDay(day) {
        if (!day)
            return [];
        const start = new Date(day.getFullYear(), day.getMonth(), day.getDate());
        const end = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 23, 59, 59);
        return root._events.filter(function (ev) {
            if (ev.allDay)
                return ev.start <= end && ev.end > start;
            return ev.start >= start && ev.start <= end;
        }).sort(root._eventSort);
    }

    function _eventTime(ev) {
        if (!ev)
            return "";
        if (ev.allDay)
            return "ALL DAY";
        const h = String(ev.start.getHours()).padStart(2, "0");
        const m = String(ev.start.getMinutes()).padStart(2, "0");
        return h + ":" + m;
    }

    function _eventEndTime(ev) {
        if (!ev || ev.allDay)
            return "";
        const h = String(ev.end.getHours()).padStart(2, "0");
        const m = String(ev.end.getMinutes()).padStart(2, "0");
        return h + ":" + m;
    }

    function _eventLastMoment(ev) {
        return new Date(Math.max(ev.start.getTime(), ev.end.getTime() - 1));
    }

    function _isMultiDay(ev) {
        if (!ev)
            return false;
        return !_sameDay(ev.start, _eventLastMoment(ev));
    }

    function _startsOnDay(ev, day) {
        return _sameDay(ev && ev.start, day);
    }

    function _endsOnDay(ev, day) {
        return _sameDay(ev ? _eventLastMoment(ev) : null, day);
    }

    function _eventStatusText(ev, day) {
        if (!ev)
            return "";
        if (!_isMultiDay(ev))
            return _eventTime(ev);
        if (_startsOnDay(ev, day))
            return ev.allDay ? "STARTS" : "STARTS " + _eventTime(ev);
        if (_endsOnDay(ev, day))
            return ev.allDay ? "ENDS" : "ENDS " + _eventEndTime(ev);
        return "CONTINUES";
    }

    function _eventSummaryForDay(ev, day) {
        if (!ev)
            return "";
        return ev.summary || "";
    }

    function _monthEventSummary(ev) {
        if (!ev)
            return "";
        const summary = ev.summary || "";
        if (ev.allDay)
            return summary;
        const time = _eventTime(ev);
        return time ? (time + " " + summary).trim() : summary;
    }

    function _abbreviateWithDots(text, maxChars) {
        const value = text || "";
        if (maxChars <= 3 || value.length <= maxChars)
            return value;
        return value.slice(0, maxChars - 3) + "...";
    }

    function _eventColor(ev) {
        if (ev && typeof ev.summary === "string" && ev.summary.includes("Geburtstag"))
            return Theme.parse("#F4511EFF", "#F4511EFF");
        return root._showColors && ev && ev.color ? Theme.parse(ev.color, "#7986CBFF") : Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.4);
    }

    function _eventOccursOnDay(ev, day) {
        if (!ev || !day)
            return false;
        const start = new Date(day.getFullYear(), day.getMonth(), day.getDate());
        const end = new Date(day.getFullYear(), day.getMonth(), day.getDate(), 23, 59, 59);
        if (ev.allDay)
            return ev.start <= end && ev.end > start;
        return ev.start >= start && ev.start <= end;
    }

    function _compactSectionHeight(rows) {
        const rowCount = rows ? rows.length : 0;
        const listHeight = rowCount === 0 ? 30 : (rowCount * 14) + (Math.max(0, rowCount - 1) * 2);
        return root._todayHeaderHeight + root._todayInnerSpacing + listHeight;
    }

    function _buildCompactRowPair(leftDay, rightDay) {
        const leftEvents = root._eventsForDay(leftDay).slice().sort(root._eventSort);
        const rightEvents = root._eventsForDay(rightDay).slice().sort(root._eventSort);
        const leftRows = [];
        const nextDay = leftDay ? new Date(leftDay) : null;
        if (nextDay)
            nextDay.setDate(nextDay.getDate() + 1);
        const sameWeekBoundary = !!(leftDay && rightDay && nextDay && root._sameDay(nextDay, rightDay) && leftDay.getDay() !== 0);

        const addRowEvent = function (rows, ev, startIndex) {
            const entry = {
                event: ev,
                text: root._monthEventSummary(ev)
            };
            let rowIndex = -1;
            for (let i = startIndex || 0; i < rows.length; i++) {
                if (!rows[i]) {
                    rowIndex = i;
                    break;
                }
            }
            if (rowIndex < 0)
                rowIndex = Math.max(rows.length, startIndex || 0);
            rows[rowIndex] = entry;
        };

        const allDayBlockEnd = function (rows) {
            let end = 0;
            for (let i = 0; i < rows.length; i++) {
                if (rows[i] && rows[i].event && rows[i].event.allDay)
                    end = i + 1;
            }
            return end;
        };

        for (const ev of leftEvents) {
            if (ev.allDay)
                addRowEvent(leftRows, ev, 0);
        }
        const leftAllDayEnd = allDayBlockEnd(leftRows);
        for (const ev of leftEvents) {
            if (!ev.allDay)
                addRowEvent(leftRows, ev, leftAllDayEnd);
        }

        const rightRows = sameWeekBoundary ? leftRows.map(function (row) {
            if (row && row.event && row.event.allDay && root._eventOccursOnDay(row.event, rightDay))
                return {
                    event: row.event,
                    text: root._monthEventSummary(row.event)
                };
            return null;
        }) : [];
        const rightHasEvent = function (ev) {
            return rightRows.some(function (row) {
                return row && row.event === ev;
            });
        };
        for (const ev of rightEvents) {
            if (ev.allDay && !rightHasEvent(ev))
                addRowEvent(rightRows, ev, 0);
        }
        const rightAllDayEnd = allDayBlockEnd(rightRows);
        for (const ev of rightEvents) {
            if (!ev.allDay)
                addRowEvent(rightRows, ev, rightAllDayEnd);
        }

        return {
            leftRows: leftRows,
            rightRows: rightRows,
            leftCount: leftEvents.length,
            rightCount: rightEvents.length
        };
    }

    function _eventSort(a, b) {
        return (+b.allDay - +a.allDay) || (a.start.getTime() - b.start.getTime()) || (a.end.getTime() - b.end.getTime()) || String(a.summary || "").localeCompare(String(b.summary || "")) || String(a.color || "").localeCompare(String(b.color || "")) || String(a._stableKey || "").localeCompare(String(b._stableKey || ""));
    }

    function _sameDay(a, b) {
        return a && b && a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }

    function _startOfDay(day) {
        if (!day)
            return null;
        return new Date(day.getFullYear(), day.getMonth(), day.getDate());
    }

    function _monthAllDayLabelDate(ev, day) {
        if (!ev || !day)
            return null;
        const weekStart = new Date(day.getFullYear(), day.getMonth(), day.getDate() - ((day.getDay() + 6) % 7));
        const weekEnd = new Date(weekStart);
        weekEnd.setDate(weekStart.getDate() + 6);
        const eventStart = root._startOfDay(ev.start);
        const eventEnd = root._startOfDay(root._eventLastMoment(ev));
        const segmentStart = new Date(Math.max(eventStart.getTime(), weekStart.getTime()));
        const segmentEnd = new Date(Math.min(eventEnd.getTime(), weekEnd.getTime()));
        const dayCount = Math.max(1, Math.floor((segmentEnd.getTime() - segmentStart.getTime()) / 86400000) + 1);
        const labelDay = new Date(segmentStart);
        labelDay.setDate(segmentStart.getDate() + Math.floor((dayCount - 1) / 2));
        return labelDay;
    }

    function _showMonthAllDayLabel(ev, day) {
        return root._sameDay(day, root._monthAllDayLabelDate(ev, day));
    }

    function _dayHeader() {
        return _sameDay(_displayDay, new Date()) ? "TODAY" : root._DAYS[_displayDay.getDay()];
    }

    function _formatCompactDayHeader(day) {
        if (!day)
            return "";
        if (root._sameDay(day, new Date()))
            return "TODAY";
        const weekday = root._DAYS[day.getDay()];
        const dd = String(day.getDate()).padStart(2, "0");
        const mm = String(day.getMonth() + 1).padStart(2, "0");
        const yyyy = String(day.getFullYear());
        return weekday + " " + dd + "." + mm + "." + yyyy;
    }

    function _setDisplayDay(day) {
        root._displayDay = day;
        SelectedDay.setSelectedDay(day);
        if (root._showMonth)
            root._buildGrid();
    }

    function _selectMonthCell(day) {
        if (!day)
            return;
        const nextDay = new Date(day);
        const monthChanged = root._viewYear !== nextDay.getFullYear() || root._viewMonth !== nextDay.getMonth();
        root._displayDay = nextDay;
        if (monthChanged) {
            root._viewYear = nextDay.getFullYear();
            root._viewMonth = nextDay.getMonth();
            root._buildGrid();
        }
        SelectedDay.setSelectedDay(nextDay);
    }

    function _resetDisplayDay() {
        const today = SelectedDay.selectedDay ? new Date(SelectedDay.selectedDay) : new Date();
        root._displayDay = today;
        root._viewYear = today.getFullYear();
        root._viewMonth = today.getMonth();
        root._buildGrid();
    }

    function _shiftMonth(delta) {
        root._viewMonth += delta;
        while (root._viewMonth > 11) {
            root._viewMonth -= 12;
            root._viewYear++;
        }
        while (root._viewMonth < 0) {
            root._viewMonth += 12;
            root._viewYear--;
        }
        root._buildGrid();
    }

    function _scrollMonthFromDelta(angleY, pixelY) {
        const delta = angleY !== 0 ? angleY : pixelY;
        if (delta === 0)
            return;
        root._shiftMonth(delta < 0 ? 1 : -1);
    }

    // ── Grid builder ──────────────────────────────────────────────────────────
    function _buildGrid() {
        const today = new Date();
        const firstDow = (new Date(_viewYear, _viewMonth, 1).getDay() + 6) % 7;
        const dim = new Date(_viewYear, _viewMonth + 1, 0).getDate();
        const visibleDates = [];
        const visibleStart = new Date(_viewYear, _viewMonth, 1 - firstDow);
        const totalCells = Math.ceil((firstDow + dim) / 7) * 7;
        const visibleEnd = new Date(visibleStart);
        visibleEnd.setDate(visibleStart.getDate() + totalCells - 1);
        visibleEnd.setHours(23, 59, 59, 999);
        for (let i = 0; i < totalCells; i++) {
            const day = new Date(visibleStart);
            day.setDate(visibleStart.getDate() + i);
            visibleDates.push(day);
        }

        const dateKey = function (day) {
            const y = day.getFullYear();
            const m = String(day.getMonth() + 1).padStart(2, "0");
            const d = String(day.getDate()).padStart(2, "0");
            return y + "-" + m + "-" + d;
        };

        const byDate = {};
        for (const day of visibleDates)
            byDate[dateKey(day)] = [];

        for (const ev of _events) {
            if (ev.allDay) {
                const cur = new Date(Math.max(ev.start.getTime(), visibleDates[0].getTime()));
                while (cur < ev.end && cur <= visibleEnd) {
                    const key = dateKey(cur);
                    if (byDate[key])
                        byDate[key].push(ev);
                    cur.setDate(cur.getDate() + 1);
                }
            } else {
                const key = dateKey(ev.start);
                if (byDate[key])
                    byDate[key].push(ev);
            }
        }

        const cells = [];
        let previousRows = [];
        for (const dayDate of visibleDates) {
            if (dayDate.getDay() === 1)
                previousRows = [];
            const isToday = root._sameDay(today, dayDate);
            const events = (byDate[dateKey(dayDate)] || []).slice().sort(root._eventSort);
            const rows = previousRows.map(function (row) {
                if (row && row.event && row.event.allDay && root._eventOccursOnDay(row.event, dayDate))
                    return row;
                return null;
            });
            const rowHasEvent = function (ev) {
                return rows.some(function (row) {
                    return row && row.event === ev;
                });
            };
            const addRowEvent = function (ev, startIndex) {
                const entry = {
                    event: ev,
                    text: root._monthEventSummary(ev)
                };
                let rowIndex = -1;
                for (let i = startIndex || 0; i < rows.length; i++) {
                    if (!rows[i]) {
                        rowIndex = i;
                        break;
                    }
                }
                if (rowIndex < 0)
                    rowIndex = Math.max(rows.length, startIndex || 0);
                rows[rowIndex] = entry;
            };

            for (const ev of events) {
                if (ev.allDay && !rowHasEvent(ev))
                    addRowEvent(ev, 0);
            }
            const allDayRowCount = rows.reduce(function (count, row) {
                return row && row.event && row.event.allDay ? count + 1 : count;
            }, 0);
            for (const ev of events) {
                if (!ev.allDay)
                    addRowEvent(ev, allDayRowCount);
            }

            const populatedRowCount = rows.reduce(function (count, row) {
                return row ? count + 1 : count;
            }, 0);
            const previewRows = rows.slice(0, root._monthPreviewCount);
            const visiblePreviewRowCount = previewRows.reduce(function (count, row) {
                return row ? count + 1 : count;
            }, 0);

            cells.push({
                day: dayDate.getDate(),
                date: dayDate,
                inMonth: dayDate.getFullYear() === _viewYear && dayDate.getMonth() === _viewMonth,
                events: events,
                rows: previewRows,
                hiddenCount: Math.max(0, populatedRowCount - visiblePreviewRowCount),
                isToday: isToday
            });
            previousRows = rows;
        }
        root._cells = cells;
    }

    Timer {
        interval: _refreshMins * 60000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._fetchAll()
    }

    Connections {
        target: SelectedDay
        function onDayChanged(day) {
            const nextDay = day ? new Date(day) : new Date();
            const sameDisplayDay = root._sameDay(root._displayDay, nextDay);
            const sameViewMonth = root._viewYear === nextDay.getFullYear() && root._viewMonth === nextDay.getMonth();
            if (sameDisplayDay && (!root._showMonth || sameViewMonth))
                return;
            root._displayDay = nextDay;
            if (root._showMonth) {
                root._viewYear = nextDay.getFullYear();
                root._viewMonth = nextDay.getMonth();
                root._buildGrid();
            }
        }
    }

    on_EventsChanged: root._buildGrid()

    onVisibleChanged: if (visible)
        root._resetDisplayDay()
    Component.onCompleted: root._resetDisplayDay()

    // ── UI ────────────────────────────────────────────────────────────────────
    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: "transparent"

        WheelHandler {
            target: null
            onWheel: event => root._scrollMonthFromDelta(event.angleDelta.y, event.pixelDelta.y)
        }

        Column {
            id: contentColumn
            anchors {
                fill: parent
                leftMargin: root._outerPadding
                rightMargin: root._outerPadding
                bottomMargin: root._outerBottomPadding
                topMargin: root._showMonth ? root._outerTopPadding : root._outerPadding
            }
            spacing: 10

            Rectangle {
                id: todayPanel
                width: parent.width
                height: root._showMonth ? root._todayPanelHeight : root._todayCompactPanelHeight
                visible: root._showToday
                radius: 16
                color: "transparent"

                Column {
                    visible: root._showMonth
                    anchors.fill: parent
                    anchors.margins: root._todayInnerMargin
                    spacing: root._todayInnerSpacing

                    Item {
                        width: parent.width
                        height: root._todayHeaderHeight
                        visible: height > 0

                        AccentText {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: root._showMonth ? root._dayHeader() : "TODAY"
                            fontFamily: Theme.fontFamily
                            fontPixelSize: 9
                            fontLetterSpacing: 1.6
                            color: (root._showMonth && root._dayHeader() === "TODAY") || !root._showMonth ? root._textColor : root._mutedText
                            backgroundVisible: (root._showMonth && root._dayHeader() === "TODAY") || !root._showMonth
                            radius: 6
                        }

                        Text {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root._displayDay.getDate() + " " + root._MONTHS[root._displayDay.getMonth()]
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: root._textColor
                            visible: root._showMonth
                        }
                    }

                    ScrollView {
                        id: eventScroll
                        width: parent.width
                        height: parent.height - y
                        leftPadding: root._todayCompactLeftPadding
                        clip: true
                        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                        ScrollBar.vertical.policy: root._displayEvents.length > 3 ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

                        Column {
                            width: eventScroll.availableWidth
                            spacing: root._showMonth ? 6 : 2

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
                                    height: root._showMonth ? 32 : 18
                                    radius: 12
                                    color: "transparent"

                                    Row {
                                        anchors.fill: parent
                                        anchors.rightMargin: 8
                                        spacing: root._showMonth ? 7 : 5

                                        Column {
                                            width: parent.width
                                            height: parent.height
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: root._showMonth ? 1 : 0

                                            Text {
                                                width: parent.width
                                                height: visible ? implicitHeight : 0
                                                visible: root._showMonth && !modelData.allDay
                                                text: root._eventStatusText(modelData, root._displayDay)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root._showMonth ? 9 : 8
                                                font.letterSpacing: 1.1
                                                color: root._mutedText
                                                elide: Text.ElideRight
                                            }

                                            Text {
                                                width: parent.width
                                                visible: root._showMonth
                                                text: root._eventSummaryForDay(modelData, root._displayDay)
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root._showMonth ? 11 : 10
                                                color: root._textColor
                                                elide: Text.ElideRight
                                            }

                                            Item {
                                                width: parent.width
                                                height: visible ? parent.height : 0
                                                visible: !root._showMonth

                                                Text {
                                                    id: compactTimeText
                                                    visible: !modelData.allDay
                                                    anchors.left: parent.left
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: root._eventTime(modelData)
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    font.letterSpacing: 1.1
                                                    color: root._eventColor(modelData)
                                                }

                                                Text {
                                                    anchors.left: compactTimeText.visible ? compactTimeText.right : parent.left
                                                    anchors.leftMargin: compactTimeText.visible ? 6 : 0
                                                    anchors.right: parent.right
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: root._eventSummaryForDay(modelData, root._displayDay)
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
                }

                Item {
                    visible: !root._showMonth
                    anchors.fill: parent

                    Row {
                        anchors.fill: parent
                        spacing: root._todayCompactColumnGap

                        Repeater {
                            model: [
                                {
                                    title: root._formatCompactDayHeader(root._displayDay),
                                    rows: root._compactDisplayRows,
                                    eventCount: root._compactDisplayCount,
                                    day: root._displayDay
                                },
                                {
                                    title: "TOMORROW",
                                    rows: root._compactTomorrowRows,
                                    eventCount: root._compactTomorrowCount,
                                    day: root._tomorrowDay
                                }
                            ]

                            delegate: Item {
                                required property var modelData
                                readonly property var sectionData: modelData

                                width: (parent.width - parent.spacing) / 2
                                height: parent.height

                                Column {
                                    anchors.fill: parent
                                    spacing: root._todayInnerSpacing

                                    Item {
                                        width: parent.width
                                        height: root._todayHeaderHeight

                                        AccentText {
                                            anchors.left: parent.left
                                            anchors.leftMargin: root._todayCompactLeftPadding
                                            anchors.verticalCenter: parent.verticalCenter
                                            text: sectionData.title
                                            fontFamily: Theme.fontFamily
                                            fontPixelSize: 9
                                            fontLetterSpacing: 1.6
                                            color: sectionData.title === "TODAY" || sectionData.title === "TOMORROW" ? root._textColor : root._mutedText
                                            backgroundVisible: sectionData.title === "TODAY" || sectionData.title === "TOMORROW"
                                            radius: 6
                                        }
                                    }

                                        ScrollView {
                                            id: compactColumnScroll
                                            width: parent.width
                                            height: parent.height - y
                                            leftPadding: root._todayCompactLeftPadding
                                            clip: true
                                            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
                                            ScrollBar.vertical.policy: sectionData.rows.length > root._todayCompactVisibleRows ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

                                            Column {
                                                width: compactColumnScroll.availableWidth
                                                spacing: root._todayCompactRowSpacing

                                            Rectangle {
                                                width: parent.width
                                                height: 30
                                                radius: 12
                                                visible: sectionData.eventCount === 0
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
                                                model: sectionData.rows

                                                delegate: Item {
                                                    required property var modelData
                                                    readonly property var rowData: modelData
                                                    readonly property var rowDay: sectionData.day
                                                    width: parent.width
                                                    height: root._todayCompactRowHeight

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        visible: !!(rowData && rowData.event && rowData.event.allDay)
                                                        radius: 4
                                                        color: "transparent"
                                                        border.width: 0
                                                        border.color: "transparent"

                                                        Row {
                                                            anchors.fill: parent
                                                            anchors.leftMargin: 2
                                                            anchors.rightMargin: 2
                                                            spacing: 4

                                                            Item {
                                                                width: Math.max(root._monthAllDayMinRuleWidth, (parent.width - compactAllDayLabel.implicitWidth - parent.spacing * 2) / 2)
                                                                height: parent.height

                                                                Rectangle {
                                                                    anchors.left: rowData && rowData.event && !root._startsOnDay(rowData.event, rowDay) ? compactLeftArrow.right : compactLeftBoundary.right
                                                                    anchors.right: parent.right
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    height: 1
                                                                    radius: 1
                                                                    color: rowData ? root._eventColor(rowData.event) : "transparent"
                                                                }

                                                                Rectangle {
                                                                    id: compactLeftBoundary
                                                                    anchors.left: parent.left
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    width: 2
                                                                    height: 7
                                                                    visible: !!(rowData && rowData.event && root._startsOnDay(rowData.event, rowDay))
                                                                    color: rowData ? root._eventColor(rowData.event) : "transparent"
                                                                }

                                                                Canvas {
                                                                    id: compactLeftArrow
                                                                    anchors.left: parent.left
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    width: 4
                                                                    height: 6
                                                                    visible: !!(rowData && rowData.event && !root._startsOnDay(rowData.event, rowDay))
                                                                    onPaint: {
                                                                        const ctx = getContext("2d");
                                                                        ctx.reset();
                                                                        ctx.fillStyle = rowData ? root._eventColor(rowData.event) : "transparent";
                                                                        ctx.beginPath();
                                                                        ctx.moveTo(width, 0);
                                                                        ctx.lineTo(0, height / 2);
                                                                        ctx.lineTo(width, height);
                                                                        ctx.closePath();
                                                                        ctx.fill();
                                                                    }
                                                                }
                                                            }

                                                            Text {
                                                                id: compactAllDayLabel
                                                                anchors.verticalCenter: parent.verticalCenter
                                                                text: root._abbreviateWithDots(rowData ? root._eventSummaryForDay(rowData.event, rowDay) : "", Math.max(6, Math.floor((parent.width - root._monthAllDayMinRuleWidth * 2 - 8) / 5.5)))
                                                                font.family: Theme.fontFamily
                                                                font.pixelSize: 9
                                                                color: root._textColor
                                                            }

                                                            Item {
                                                                width: Math.max(root._monthAllDayMinRuleWidth, (parent.width - compactAllDayLabel.implicitWidth - parent.spacing * 2) / 2)
                                                                height: parent.height

                                                                Rectangle {
                                                                    anchors.left: parent.left
                                                                    anchors.right: rowData && rowData.event && !root._endsOnDay(rowData.event, rowDay) ? compactRightArrow.left : compactRightBoundary.left
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    height: 1
                                                                    radius: 1
                                                                    color: rowData ? root._eventColor(rowData.event) : "transparent"
                                                                }

                                                                Rectangle {
                                                                    id: compactRightBoundary
                                                                    anchors.right: parent.right
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    width: 2
                                                                    height: 7
                                                                    visible: !!(rowData && rowData.event && root._endsOnDay(rowData.event, rowDay))
                                                                    color: rowData ? root._eventColor(rowData.event) : "transparent"
                                                                }

                                                                Canvas {
                                                                    id: compactRightArrow
                                                                    anchors.right: parent.right
                                                                    anchors.verticalCenter: parent.verticalCenter
                                                                    width: 4
                                                                    height: 6
                                                                    visible: !!(rowData && rowData.event && !root._endsOnDay(rowData.event, rowDay))
                                                                    onPaint: {
                                                                        const ctx = getContext("2d");
                                                                        ctx.reset();
                                                                        ctx.fillStyle = rowData ? root._eventColor(rowData.event) : "transparent";
                                                                        ctx.beginPath();
                                                                        ctx.moveTo(0, 0);
                                                                        ctx.lineTo(width, height / 2);
                                                                        ctx.lineTo(0, height);
                                                                        ctx.closePath();
                                                                        ctx.fill();
                                                                    }
                                                                }
                                                            }
                                                        }
                                                    }

                                                    Row {
                                                        anchors.fill: parent
                                                        visible: !!(rowData && rowData.event && !rowData.event.allDay)
                                                        spacing: 4

                                                        Text {
                                                            id: compactTimedLabel
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: rowData ? root._eventTime(rowData.event) : ""
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 8
                                                            font.letterSpacing: 1.1
                                                            color: root._mutedText
                                                        }

                                                        Text {
                                                            width: parent.width - x
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            text: rowData ? root._eventSummaryForDay(rowData.event, rowDay) : ""
                                                            font.family: Theme.fontFamily
                                                            font.pixelSize: 9
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
                        }
                    }
                }
            }

            Column {
                id: monthPanel
                width: parent.width
                visible: root._showMonth
                spacing: 0

                Item {
                    width: parent.width
                    height: 20

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 8

                        AccentText {
                            text: root._MONTHS[root._viewMonth]
                            fontFamily: Theme.fontFamily
                            fontPixelSize: 9
                            fontLetterSpacing: 1.6
                            color: root._textColor
                            radius: 6
                        }

                        Text {
                            text: root._viewYear
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            color: root._textColor
                        }
                    }
                }

                Row {
                    width: parent.width
                    height: 10

                    Repeater {
                        model: root._DOW
                        delegate: Text {
                            width: parent.width / 7
                            text: modelData
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
                    height: root._gridRows * root._monthCellHeight + (root._gridRows - 1) * rowSpacing
                    rowSpacing: 4
                    columnSpacing: 1

                    Repeater {
                        model: root._cells

                        delegate: Rectangle {
                            required property var modelData
                            property var cell: modelData
                            readonly property bool isSelected: root._sameDay(root._displayDay, cell.date)

                            width: (calGrid.width - calGrid.columnSpacing * 6) / 7
                            height: root._monthCellHeight
                            radius: 10
                            color: "transparent"
                            border.width: 0
                            border.color: "transparent"

                            Rectangle {
                                anchors.fill: parent
                                anchors.topMargin: cell.isToday ? -3 : 0
                                anchors.bottomMargin: cell.isToday ? 0 : 0
                                radius: parent.radius
                                color: cell.isToday ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.15) : "transparent"
                            }

                            Column {
                                anchors.fill: parent
                                anchors.leftMargin: root._monthContentSideMargin
                                anchors.rightMargin: root._monthContentSideMargin
                                anchors.topMargin: root._monthContentTopMargin
                                anchors.bottomMargin: root._monthContentBottomMargin
                                spacing: root._monthContentSpacing

                                Item {
                                    width: parent.width
                                    height: root._monthHeaderHeight

                                    AccentText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: String(cell.day || "")
                                        fontFamily: Theme.fontFamily
                                        fontPixelSize: 10
                                        color: cell.isToday ? root._textColor : (isSelected ? root._textColor : (cell.inMonth ? root._mutedText : Qt.rgba(root._mutedText.r, root._mutedText.g, root._mutedText.b, 0.45)))
                                        backgroundVisible: cell.isToday
                                        radius: 6
                                        paddingX: 3
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: cell.hiddenCount > 0
                                        text: "+" + String(cell.hiddenCount) + " more"
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 7
                                        color: root._mutedText
                                        elide: Text.ElideRight
                                    }
                                }

                                Column {
                                    width: parent.width
                                    spacing: root._monthEventListSpacing
                                    visible: cell.events.length > 0

                                    Repeater {
                                        model: root._monthPreviewCount
                                        delegate: Item {
                                            readonly property var rowData: cell.rows[index]
                                            readonly property var rowDay: cell.date
                                            readonly property bool showAllDayLabel: !!(rowData && rowData.event && root._showMonthAllDayLabel(rowData.event, rowDay))
                                            width: parent.width
                                            height: root._monthEventRowHeight

                                            Rectangle {
                                                anchors.fill: parent
                                                visible: !!(rowData && rowData.event && rowData.event.allDay)
                                                radius: 4
                                                color: "transparent"
                                                border.width: 0
                                                border.color: "transparent"

                                                Row {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 2
                                                    anchors.rightMargin: 2
                                                    spacing: showAllDayLabel ? 4 : 0

                                                    Item {
                                                        width: Math.max(root._monthAllDayMinRuleWidth, showAllDayLabel ? (parent.width - monthAllDayLabel.implicitWidth - parent.spacing * 2) / 2 : parent.width / 2)
                                                        height: parent.height

                                                        Rectangle {
                                                            anchors.left: rowData && rowData.event && !root._startsOnDay(rowData.event, rowDay) ? leftArrow.right : leftBoundary.right
                                                            anchors.right: parent.right
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            height: 1
                                                            radius: 1
                                                            color: rowData ? root._eventColor(rowData.event) : "transparent"
                                                        }

                                                        Rectangle {
                                                            id: leftBoundary
                                                            anchors.left: parent.left
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: 2
                                                            height: 7
                                                            visible: !!(rowData && rowData.event && root._startsOnDay(rowData.event, rowDay))
                                                            color: rowData ? root._eventColor(rowData.event) : "transparent"
                                                        }

                                                        Canvas {
                                                            id: leftArrow
                                                            anchors.left: parent.left
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: 4
                                                            height: 6
                                                            visible: !!(rowData && rowData.event && !root._startsOnDay(rowData.event, rowDay))
                                                            onPaint: {
                                                                const ctx = getContext("2d");
                                                                ctx.reset();
                                                                ctx.fillStyle = rowData ? root._eventColor(rowData.event) : "transparent";
                                                                ctx.beginPath();
                                                                ctx.moveTo(width, 0);
                                                                ctx.lineTo(0, height / 2);
                                                                ctx.lineTo(width, height);
                                                                ctx.closePath();
                                                                ctx.fill();
                                                            }
                                                        }
                                                    }

                                                    Text {
                                                        id: monthAllDayLabel
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        visible: showAllDayLabel
                                                        text: rowData && rowData.event ? root._abbreviateWithDots(root._eventSummaryForDay(rowData.event, rowDay), Math.max(6, Math.floor((parent.width - root._monthAllDayMinRuleWidth * 2 - 8) / 5.5))) : ""
                                                        font.family: Theme.fontFamily
                                                        font.pixelSize: 9
                                                        color: root._textColor
                                                    }

                                                    Item {
                                                        width: Math.max(root._monthAllDayMinRuleWidth, showAllDayLabel ? (parent.width - monthAllDayLabel.implicitWidth - parent.spacing * 2) / 2 : parent.width / 2)
                                                        height: parent.height

                                                        Rectangle {
                                                            anchors.left: parent.left
                                                            anchors.right: rowData && rowData.event && !root._endsOnDay(rowData.event, rowDay) ? rightArrow.left : rightBoundary.left
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            height: 1
                                                            radius: 1
                                                            color: rowData ? root._eventColor(rowData.event) : "transparent"
                                                        }

                                                        Rectangle {
                                                            id: rightBoundary
                                                            anchors.right: parent.right
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: 2
                                                            height: 7
                                                            visible: !!(rowData && rowData.event && root._endsOnDay(rowData.event, rowDay))
                                                            color: rowData ? root._eventColor(rowData.event) : "transparent"
                                                        }

                                                        Canvas {
                                                            id: rightArrow
                                                            anchors.right: parent.right
                                                            anchors.verticalCenter: parent.verticalCenter
                                                            width: 4
                                                            height: 6
                                                            visible: !!(rowData && rowData.event && !root._endsOnDay(rowData.event, rowDay))
                                                            onPaint: {
                                                                const ctx = getContext("2d");
                                                                ctx.reset();
                                                                ctx.fillStyle = rowData ? root._eventColor(rowData.event) : "transparent";
                                                                ctx.beginPath();
                                                                ctx.moveTo(0, 0);
                                                                ctx.lineTo(width, height / 2);
                                                                ctx.lineTo(0, height);
                                                                ctx.closePath();
                                                                ctx.fill();
                                                            }
                                                        }
                                                    }
                                                }
                                            }

                                            Row {
                                                anchors.fill: parent
                                                visible: !!(rowData && rowData.event && !rowData.event.allDay)
                                                spacing: 4

                                                Text {
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    id: monthTimedEventTime
                                                    text: rowData ? root._eventTime(rowData.event) : ""
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 8
                                                    font.letterSpacing: 1.1
                                                    color: root._mutedText
                                                }

                                                Text {
                                                    width: parent.width - x
                                                    anchors.verticalCenter: parent.verticalCenter
                                                    text: rowData && rowData.event ? root._eventSummaryForDay(rowData.event, rowDay) : ""
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    color: root._textColor
                                                    elide: Text.ElideRight
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !!cell.date
                                onClicked: root._selectMonthCell(cell.date)
                                onWheel: wheel => root._scrollMonthFromDelta(wheel.angleDelta.y, wheel.pixelDelta.y)
                            }
                        }
                    }
                }
            }
        }
    }
}
