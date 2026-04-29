import QtQuick 2.15
import Quickshell
import Quickshell.Io
import "../lib"

Item {
    id: root

    property var moduleConfig: null
    property int preferredHeight: 300

    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property color _mutedColor: Qt.rgba(_textColor.r, _textColor.g, _textColor.b, 0.62)
    readonly property color _cardColor: Qt.rgba(1, 1, 1, 0.04)
    readonly property var _cfg: moduleConfig ? (moduleConfig.props || {}) : {}
    readonly property string _email: _cfg.email || ""
    readonly property string _password: _cfg.password || ""
    readonly property int _intervalMin: _cfg.refreshInterval || 10

    property var _hrv28Days: []
    property string _hrvStatus: ""
    property int _hrvBaselineLow: 0
    property int _hrvBaselineHigh: 0
    property int _hrvLowUpper: 0
    property var _steps7Days: []
    property int _restingHeartRate: 0
    property int _stressToday: 0
    property var _stress7Days: []
    property var _lastNightSleep: null
    property var _sleep7Days: []
    property int _sleepNeedToday: 0
    property int _vo2Max: 0
    property int _marathonPredictionSeconds: 0
    property int _enduranceScore: 0
    property int _enduranceClassification: 0
    property var _endurance26Weeks: []
    property bool _fetching: false
    property string _status: ""

    readonly property string _scriptPath: Quickshell.shellPath("scripts/garmin_fetch.py")
    readonly property string _tokenStore: Quickshell.dataPath("garmin-tokens")

    function _formatDuration(totalSeconds) {
        const value = Number(totalSeconds);
        if (!isFinite(value) || value <= 0)
            return "—";
        const rounded = Math.round(value);
        const hours = Math.floor(rounded / 3600);
        const minutes = Math.floor((rounded % 3600) / 60);
        if (hours <= 0)
            return minutes + "m";
        return hours + "h " + String(minutes).padStart(2, "0") + "m";
    }

    function _formatRaceTime(totalSeconds) {
        const value = Number(totalSeconds);
        if (!isFinite(value) || value <= 0)
            return "—";
        const rounded = Math.round(value);
        const hours = Math.floor(rounded / 3600);
        const minutes = Math.floor((rounded % 3600) / 60);
        const seconds = rounded % 60;
        return hours + ":" + String(minutes).padStart(2, "0") + ":" + String(seconds).padStart(2, "0");
    }

    function _shortDayLabel(isoDate) {
        if (!isoDate)
            return "";
        const parsed = new Date(isoDate + "T00:00:00");
        const labels = ["S", "M", "T", "W", "T", "F", "S"];
        return labels[parsed.getDay()];
    }

    function _seriesMax(items, key, fallback) {
        let maxValue = 0;
        for (const item of items || []) {
            const value = Number(item[key]);
            if (isFinite(value) && value > maxValue)
                maxValue = value;
        }
        return Math.max(maxValue, fallback || 1);
    }

    function _clamp(value, minValue, maxValue) {
        return Math.max(minValue, Math.min(maxValue, value));
    }

    function _mix(a, b, t) {
        const f = _clamp(t, 0, 1);
        return a + (b - a) * f;
    }

    function _metricRatio(field, value) {
        const numeric = Number(value) || 0;
        if (field === "sleepSeconds")
            return _clamp((numeric - 21600) / (30600 - 21600), 0, 1);
        if (field === "sleepScore")
            return _clamp((numeric - 50) / (100 - 50), 0, 1);
        if (field === "stress")
            return _clamp((100 - numeric) / 100, 0, 1);
        return 0.5;
    }

    function _metricColor(field, value) {
        const ratio = _metricRatio(field, value);
        const bad = {
            r: 1.00,
            g: 0.36,
            b: 0.36
        };
        const good = {
            r: 0.38,
            g: 1.00,
            b: 0.49
        };
        const accentTint = 0.34;
        const baseR = _mix(bad.r, good.r, ratio);
        const baseG = _mix(bad.g, good.g, ratio);
        const baseB = _mix(bad.b, good.b, ratio);
        return Qt.rgba(_mix(baseR, root._accentColor.r, accentTint), _mix(baseG, root._accentColor.g, accentTint), _mix(baseB, root._accentColor.b, accentTint), 0.88);
    }

    function _chartData() {
        const sleepByDate = {};
        for (const item of _sleep7Days || [])
            sleepByDate[item.date] = item;

        const merged = [];
        for (const item of _stress7Days || []) {
            const sleep = sleepByDate[item.date] || {};
            merged.push({
                date: item.date,
                label: _shortDayLabel(item.date),
                stress: Number(item.averageStressLevel) || 0,
                sleepSeconds: Number(sleep.sleepTimeSeconds) || 0,
                sleepScore: Number(sleep.sleepScore) || 0
            });
        }

        for (const item of _sleep7Days || []) {
            if ((merged.findIndex(function (entry) {
                    return entry.date === item.date;
                }) >= 0))
                continue;
            merged.push({
                date: item.date,
                label: _shortDayLabel(item.date),
                stress: 0,
                sleepSeconds: Number(item.sleepTimeSeconds) || 0,
                sleepScore: Number(item.sleepScore) || 0
            });
        }

        merged.sort(function (a, b) {
            return a.date.localeCompare(b.date);
        });
        return merged;
    }

    readonly property var _weekChart: _chartData()
    readonly property real _chartStressMax: _seriesMax(_weekChart, "stress", 100)
    readonly property real _chartSleepMax: _seriesMax(_weekChart, "sleepSeconds", 28800)
    readonly property real _chartScoreMax: _seriesMax(_weekChart, "sleepScore", 100)
    readonly property real _chartStepsMax: _seriesMax(_steps7Days, "steps", 10000)
    readonly property real _chartEnduranceMin: 3000
    readonly property real _chartEnduranceMax: 9000

    readonly property int _hrvToday: _hrv28Days.length > 0 ? _hrv28Days[_hrv28Days.length - 1].hrv : 0
    readonly property string _hrvStatusLabel: {
        const map = { "BALANCED": "Balanced", "UNBALANCED": "Unbalanced", "POOR": "Poor", "LOW": "Low" };
        return map[_hrvStatus] || _hrvStatus;
    }
    readonly property real _chartHrvMin: {
        let min = Infinity;
        for (const item of _hrv28Days) if (item.hrv < min) min = item.hrv;
        return isFinite(min) ? Math.max(0, min - 5) : 0;
    }
    readonly property real _chartHrvMax: _seriesMax(_hrv28Days, "hrv", 60) + 5

    readonly property string _enduranceTierLabel: {
        const tiers = ["Untrained", "Recreational", "Intermediate", "Trained", "Well Trained", "Expert", "Superior", "Elite"];
        return tiers[Math.max(0, Math.min(7, _enduranceClassification))];
    }

    Process {
        id: fetchProc
        command: ["python3", root._scriptPath, root._email, root._password, root._tokenStore]
        running: false
        stdout: StdioCollector {
            id: fetchStdio
        }
        onExited: {
            root._fetching = false;
            const lines = fetchStdio.text.trim().split("\n").filter(l => l.trim() !== "");
            const lastLine = lines.length > 0 ? lines[lines.length - 1] : "";
            try {
                const data = JSON.parse(lastLine);
                if (data.error) {
                    if (data.error === "no_tokens") {
                        root._status = "setup needed — run garmin_setup.py";
                        refreshTimer.interval = 30000;
                    } else if (data.error.startsWith("rate_limited")) {
                        root._status = "rate limited — retry in 60 min";
                        refreshTimer.interval = 3600000;
                    } else {
                        root._status = data.error;
                        refreshTimer.interval = root._intervalMin * 60000;
                    }
                } else {
                    root._hrv28Days = data.hrv28Days || [];
                    root._hrvStatus = data.hrvStatus || "";
                    root._hrvBaselineLow = data.hrvBaselineLow || 0;
                    root._hrvBaselineHigh = data.hrvBaselineHigh || 0;
                    root._hrvLowUpper = data.hrvLowUpper || 0;
                    root._steps7Days = data.steps7Days || [];
                    root._restingHeartRate = data.restingHeartRate || 0;
                    root._stressToday = data.averageStressLevelToday || 0;
                    root._stress7Days = data.averageStressLevel7Days || [];
                    root._lastNightSleep = data.lastNightSleep || null;
                    root._sleep7Days = data.sleep7Days || [];
                    root._sleepNeedToday = data.sleepNeedToday || 0;
                    root._vo2Max = data.vo2Max || 0;
                    root._marathonPredictionSeconds = data.marathonPredictionSeconds || 0;
                    root._enduranceScore = data.enduranceScore || 0;
                    root._enduranceClassification = data.enduranceClassification || 0;
                    root._endurance26Weeks = data.endurance26Weeks || [];
                    root._status = "";
                    refreshTimer.interval = root._intervalMin * 60000;
                }
            } catch (e) {
                root._status = "parse error: " + lastLine.substring(0, 60);
                refreshTimer.interval = root._intervalMin * 60000;
            }
        }
    }

    Timer {
        id: refreshTimer
        interval: root._intervalMin * 60000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._fetch()
    }

    function _fetch() {
        if (_fetching || !_email || !_password)
            return;
        _fetching = true;
        fetchProc.running = true;
    }

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root._status !== "" ? root._status : ""
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: root._mutedColor
            visible: text !== ""
        }

        Rectangle {
            width: parent.width
            height: 88
            radius: 8
            color: root._cardColor
            visible: root._endurance26Weeks.length > 0

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                Item {
                    width: parent.width
                    height: 12

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Endurance"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 0.8
                        color: root._mutedColor
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._enduranceTierLabel
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: root._textColor
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._enduranceScore > 0 ? String(root._enduranceScore) : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: root._accentColor
                        visible: text !== ""
                    }
                }

                Canvas {
                    id: enduranceCanvas
                    width: parent.width
                    height: 62

                    property var chartData: root._endurance26Weeks
                    property real chartMin: root._chartEnduranceMin
                    property real chartMax: root._chartEnduranceMax

                    onChartDataChanged: requestPaint()
                    onChartMinChanged: requestPaint()
                    onChartMaxChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        var data = chartData;
                        if (!data || data.length < 2) return;

                        var n = data.length;
                        var hpad = 4;
                        var vpad = 4;
                        var bpad = 10;
                        var r = 6;
                        var range = chartMax - chartMin;

                        function xAt(i) { return hpad + i * (width - 2 * hpad) / (n - 1); }
                        function yAt(s) { return vpad + (height - vpad - bpad) * (1 - (s - chartMin) / range); }

                        ctx.save();
                        ctx.beginPath();
                        ctx.moveTo(r, 0);
                        ctx.lineTo(width - r, 0);
                        ctx.arcTo(width, 0, width, r, r);
                        ctx.lineTo(width, height - r);
                        ctx.arcTo(width, height, width - r, height, r);
                        ctx.lineTo(r, height);
                        ctx.arcTo(0, height, 0, height - r, r);
                        ctx.lineTo(0, r);
                        ctx.arcTo(0, 0, r, 0, r);
                        ctx.closePath();
                        ctx.clip();

                        var grad = ctx.createLinearGradient(0, 0, 0, height);
                        var stops = [
                            { score: 9000, color: "rgba(236,72,153,0.28)" },
                            { score: 8900, color: "rgba(236,72,153,0.28)" },
                            { score: 8450, color: "rgba(147,51,234,0.28)" },
                            { score: 7700, color: "rgba(59,130,246,0.28)" },
                            { score: 6950, color: "rgba(34,197,94,0.28)" },
                            { score: 6200, color: "rgba(234,179,8,0.28)" },
                            { score: 5450, color: "rgba(249,115,22,0.28)" },
                            { score: 4335, color: "rgba(239,68,68,0.28)" },
                            { score: 3000, color: "rgba(239,68,68,0.28)" },
                        ];
                        for (var t = 0; t < stops.length; t++) {
                            var pos = (chartMax - stops[t].score) / (chartMax - chartMin);
                            grad.addColorStop(Math.max(0, Math.min(1, pos)), stops[t].color);
                        }
                        ctx.fillStyle = grad;
                        ctx.fillRect(0, 0, width, height);
                        ctx.restore();

                        var col = String(root._accentColor);

                        ctx.beginPath();
                        ctx.moveTo(xAt(0), yAt(data[0].score));
                        for (var i = 1; i < n; i++)
                            ctx.lineTo(xAt(i), yAt(data[i].score));
                        ctx.strokeStyle = col;
                        ctx.lineWidth = 1.5;
                        ctx.lineJoin = "round";
                        ctx.globalAlpha = 0.75;
                        ctx.stroke();

                        ctx.globalAlpha = 1.0;
                        for (var j = 0; j < n; j++) {
                            ctx.beginPath();
                            ctx.arc(xAt(j), yAt(data[j].score), 2.5, 0, Math.PI * 2);
                            ctx.fillStyle = col;
                            ctx.fill();
                        }
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 88
            radius: 8
            color: root._cardColor
            visible: root._hrv28Days.length > 0

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                Item {
                    width: parent.width
                    height: 12

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "HRV"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 0.8
                        color: root._mutedColor
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._hrvStatusLabel
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: root._textColor
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: root._hrvToday > 0 ? String(root._hrvToday) : ""
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: root._accentColor
                        visible: text !== ""
                    }
                }

                Canvas {
                    id: hrvCanvas
                    width: parent.width
                    height: 62

                    property var chartData: root._hrv28Days
                    property real chartMin: root._chartHrvMin
                    property real chartMax: root._chartHrvMax
                    property real baselineLow: root._hrvBaselineLow
                    property real baselineHigh: root._hrvBaselineHigh
                    property real lowUpper: root._hrvLowUpper

                    onChartDataChanged: requestPaint()
                    onChartMinChanged: requestPaint()
                    onChartMaxChanged: requestPaint()
                    onBaselineLowChanged: requestPaint()
                    onBaselineHighChanged: requestPaint()
                    onLowUpperChanged: requestPaint()

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        var data = chartData;
                        if (!data || data.length < 2) return;

                        var n = data.length;
                        var hpad = 4;
                        var vpad = 4;
                        var bpad = 14;
                        var r = 6;
                        var range = chartMax - chartMin;
                        if (range <= 0) return;

                        function xAt(i) { return hpad + i * (width - 2 * hpad) / (n - 1); }
                        function yAt(s) { return vpad + (height - vpad - bpad) * (1 - (s - chartMin) / range); }
                        function posAt(s) {
                            return Math.max(0, Math.min(1,
                                (vpad + (height - vpad - bpad) * (1 - (s - chartMin) / range)) / height));
                        }

                        ctx.save();
                        ctx.beginPath();
                        ctx.moveTo(r, 0);
                        ctx.lineTo(width - r, 0);
                        ctx.arcTo(width, 0, width, r, r);
                        ctx.lineTo(width, height - r);
                        ctx.arcTo(width, height, width - r, height, r);
                        ctx.lineTo(r, height);
                        ctx.arcTo(0, height, 0, height - r, r);
                        ctx.lineTo(0, r);
                        ctx.arcTo(0, 0, r, 0, r);
                        ctx.closePath();
                        ctx.clip();

                        var bLow  = baselineLow  > 0 ? baselineLow  : chartMin + range * 0.35;
                        var bHigh = baselineHigh > 0 ? baselineHigh : chartMin + range * 0.65;
                        var aboveStop = bHigh + (chartMax - bHigh) * 0.5;
                        var belowStop = bLow  - (bLow  - chartMin) * 0.5;

                        var grad = ctx.createLinearGradient(0, 0, 0, height);
                        grad.addColorStop(0,                  "rgba(239,68,68,0.28)");
                        grad.addColorStop(posAt(aboveStop),   "rgba(249,115,22,0.28)");
                        grad.addColorStop(posAt(bHigh),       "rgba(34,197,94,0.28)");
                        grad.addColorStop(posAt(bLow),        "rgba(34,197,94,0.28)");
                        grad.addColorStop(posAt(belowStop),   "rgba(249,115,22,0.28)");
                        grad.addColorStop(1,                  "rgba(239,68,68,0.28)");
                        ctx.fillStyle = grad;
                        ctx.fillRect(0, 0, width, height);

                        // Balanced zone band
                        if (baselineLow > chartMin && baselineHigh > chartMin) {
                            ctx.fillStyle = "rgba(34,197,94,0.10)";
                            ctx.fillRect(hpad, yAt(baselineHigh), width - 2 * hpad, yAt(baselineLow) - yAt(baselineHigh));
                        }

                        // Low threshold dashed line
                        if (lowUpper > chartMin && lowUpper < chartMax) {
                            ctx.save();
                            ctx.setLineDash([3, 4]);
                            ctx.strokeStyle = "rgba(249,115,22,0.55)";
                            ctx.lineWidth = 1;
                            ctx.beginPath();
                            ctx.moveTo(hpad, yAt(lowUpper));
                            ctx.lineTo(width - hpad, yAt(lowUpper));
                            ctx.stroke();
                            ctx.restore();
                        }

                        var col = String(root._accentColor);

                        // Smooth bezier curve through midpoints
                        ctx.beginPath();
                        ctx.moveTo(xAt(0), yAt(data[0].hrv));
                        for (var i = 0; i < n - 1; i++) {
                            var midX = (xAt(i) + xAt(i + 1)) / 2;
                            var midY = (yAt(data[i].hrv) + yAt(data[i + 1].hrv)) / 2;
                            ctx.quadraticCurveTo(xAt(i), yAt(data[i].hrv), midX, midY);
                        }
                        ctx.lineTo(xAt(n - 1), yAt(data[n - 1].hrv));
                        ctx.strokeStyle = col;
                        ctx.lineWidth = 1.5;
                        ctx.lineJoin = "round";
                        ctx.globalAlpha = 0.75;
                        ctx.stroke();
                        ctx.globalAlpha = 1.0;

                        // Past data dots (small)
                        for (var j = 0; j < n - 1; j++) {
                            ctx.beginPath();
                            ctx.arc(xAt(j), yAt(data[j].hrv), 1.5, 0, Math.PI * 2);
                            ctx.fillStyle = col;
                            ctx.globalAlpha = 0.55;
                            ctx.fill();
                            ctx.globalAlpha = 1.0;
                        }

                        // Today dot (larger, white center)
                        ctx.beginPath();
                        ctx.arc(xAt(n - 1), yAt(data[n - 1].hrv), 3.5, 0, Math.PI * 2);
                        ctx.fillStyle = col;
                        ctx.fill();
                        ctx.beginPath();
                        ctx.arc(xAt(n - 1), yAt(data[n - 1].hrv), 1.5, 0, Math.PI * 2);
                        ctx.fillStyle = "rgba(255,255,255,0.9)";
                        ctx.fill();

                        // X-axis date labels every 7 days
                        var monthAbbr = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
                        ctx.font = "7px sans-serif";
                        ctx.textAlign = "center";
                        ctx.fillStyle = "rgba(255,255,255,0.38)";
                        var labelIdxs = [0];
                        for (var k = 7; k < n; k += 7) labelIdxs.push(k);
                        if (labelIdxs[labelIdxs.length - 1] !== n - 1) labelIdxs.push(n - 1);
                        for (var li = 0; li < labelIdxs.length; li++) {
                            var idx = labelIdxs[li];
                            var parts = data[idx].date.split("-");
                            ctx.fillText(monthAbbr[parseInt(parts[1]) - 1] + " " + parseInt(parts[2]), xAt(idx), height - 3);
                        }

                        ctx.restore();
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 88
            radius: 8
            color: root._cardColor
            visible: root._steps7Days.length > 0

            Column {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                Item {
                    width: parent.width
                    height: 12

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Steps"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 0.8
                        color: root._mutedColor
                    }

                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            const last = root._steps7Days[root._steps7Days.length - 1];
                            return last && last.steps > 0 ? last.steps.toLocaleString() : "";
                        }
                        font.family: Theme.fontFamily
                        font.pixelSize: 10
                        font.bold: true
                        color: root._accentColor
                        visible: text !== ""
                    }
                }

                Row {
                    id: stepsChartRow
                    width: parent.width
                    height: 62
                    spacing: 4

                    Repeater {
                        model: root._steps7Days

                        delegate: Item {
                            width: (stepsChartRow.width - stepsChartRow.spacing * 6) / 7
                            height: stepsChartRow.height

                            Rectangle {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                width: Math.max(6, parent.width - 4)
                                height: Math.max(2, parent.height * (modelData.steps / Math.max(1, root._chartStepsMax)))
                                radius: 3
                                color: root._accentColor
                                opacity: 0.75
                            }
                        }
                    }
                }
            }
        }

        Grid {
            id: topMetricsGrid
            width: parent.width
            columns: 3
            rowSpacing: 8
            columnSpacing: 8

            Repeater {
                model: [
                    {
                        label: "Resting HR",
                        value: root._restingHeartRate > 0 ? root._restingHeartRate + " bpm" : "—"
                    },
                    {
                        label: "VO2 max",
                        value: root._vo2Max > 0 ? String(root._vo2Max) : "—"
                    },
                    {
                        label: "Marathon",
                        value: root._formatRaceTime(root._marathonPredictionSeconds)
                    }
                ]

                delegate: Rectangle {
                    width: (topMetricsGrid.width - (topMetricsGrid.columnSpacing * 2)) / 3
                    height: 42
                    radius: 8
                    color: root._cardColor

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 2

                        Text {
                            text: modelData.label
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 0.8
                            color: root._mutedColor
                            elide: Text.ElideRight
                        }

                        Text {
                            text: modelData.value
                            font.family: Theme.fontFamily
                            font.pixelSize: 13
                            color: root._textColor
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }

        Row {
            id: chartsRow
            width: parent.width
            height: 104
            spacing: 8

            Repeater {
                model: [
                    {
                        label: "Sleep Time",
                        field: "sleepSeconds",
                        maxValue: root._chartSleepMax
                    },
                    {
                        label: "Sleep Score",
                        field: "sleepScore",
                        maxValue: root._chartScoreMax
                    },
                    {
                        label: "Stress",
                        field: "stress",
                        maxValue: root._chartStressMax
                    }
                ]

                delegate: Rectangle {
                    id: chartCard
                    property string chartLabel: modelData.label
                    property string chartField: modelData.field
                    property real chartMaxValue: modelData.maxValue
                    width: (chartsRow.width - (chartsRow.spacing * 2)) / 3
                    height: chartsRow.height
                    radius: 8
                    color: root._cardColor

                    Column {
                        anchors.fill: parent
                        anchors.margins: 8
                        spacing: 6

                        Item {
                            width: parent.width
                            height: 12

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: chartCard.chartLabel
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.letterSpacing: 0.8
                                color: root._mutedColor
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: {
                                    if (chartCard.chartField === "sleepScore" && root._lastNightSleep && root._lastNightSleep.sleepScore > 0)
                                        return String(root._lastNightSleep.sleepScore);
                                    if (chartCard.chartField === "stress" && root._stressToday > 0)
                                        return String(root._stressToday);
                                    if (chartCard.chartField === "sleepSeconds" && root._lastNightSleep && root._lastNightSleep.sleepTimeSeconds > 0)
                                        return root._formatDuration(root._lastNightSleep.sleepTimeSeconds);
                                    return "";
                                }
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                color: {
                                    if (chartCard.chartField === "sleepScore" && root._lastNightSleep)
                                        return root._metricColor(chartCard.chartField, root._lastNightSleep.sleepScore);
                                    if (chartCard.chartField === "stress")
                                        return root._metricColor(chartCard.chartField, root._stressToday);
                                    if (chartCard.chartField === "sleepSeconds" && root._lastNightSleep)
                                        return root._metricColor(chartCard.chartField, root._lastNightSleep.sleepTimeSeconds);
                                    return root._textColor;
                                }
                                visible: text !== ""
                            }
                        }

                        Row {
                            id: singleChartRow
                            width: parent.width
                            height: 74
                            spacing: 4

                            Repeater {
                                model: root._weekChart

                                delegate: Item {
                                    width: (singleChartRow.width - (singleChartRow.spacing * 6)) / 7
                                    height: singleChartRow.height

                                    Item {
                                        anchors.fill: parent

                                        Rectangle {
                                            id: chartBar
                                            anchors.horizontalCenter: parent.horizontalCenter
                                            anchors.bottom: parent.bottom
                                            width: 6
                                            height: Math.max(2, parent.height * ((Number(modelData[chartCard.chartField]) || 0) / Math.max(1, chartCard.chartMaxValue)))
                                            radius: 3
                                            color: root._metricColor(chartCard.chartField, modelData[chartCard.chartField])
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
            width: parent.width
            height: 20
            visible: root._fetching

            Item {
                id: spinnerItem
                width: 18
                height: 18
                anchors.centerIn: parent

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.beginPath();
                        ctx.arc(width / 2, height / 2, 7, 0, Math.PI * 1.5);
                        ctx.strokeStyle = String(root._accentColor);
                        ctx.lineWidth = 2;
                        ctx.lineCap = "round";
                        ctx.stroke();
                    }
                }

                RotationAnimator {
                    target: spinnerItem
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    running: root._fetching
                }
            }
        }
    }
}
