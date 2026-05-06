import QtQuick 2.15
import Quickshell
import Quickshell.Io
import "../lib"

Item {
    id: root

    property var moduleConfig: null
    readonly property int preferredHeight: mainColumn.implicitHeight + 10

    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property color _mutedColor: Qt.rgba(_textColor.r, _textColor.g, _textColor.b, 0.62)

    readonly property var _hrv28Days: GarminState.hrv28Days
    readonly property string _hrvStatus: GarminState.hrvStatus
    readonly property int _hrvBaselineLow: GarminState.hrvBaselineLow
    readonly property int _hrvBaselineHigh: GarminState.hrvBaselineHigh
    readonly property int _hrvLowUpper: GarminState.hrvLowUpper
    readonly property int _hrvWeeklyAvg: GarminState.hrvWeeklyAvg
    readonly property var _steps7Days: GarminState.steps7Days
    readonly property int _restingHeartRate: GarminState.restingHeartRate
    readonly property int _stressToday: GarminState.stressToday
    readonly property var _stress7Days: GarminState.stress7Days
    readonly property var _lastNightSleep: GarminState.lastNightSleep
    readonly property var _sleep7Days: GarminState.sleep7Days
    readonly property int _sleepNeedToday: GarminState.sleepNeedToday
    readonly property int _vo2Max: GarminState.vo2Max
    readonly property int _marathonPredictionSeconds: GarminState.marathonPredictionSeconds
    readonly property int _enduranceScore: GarminState.enduranceScore
    readonly property int _enduranceClassification: GarminState.enduranceClassification
    readonly property var _endurance26Weeks: GarminState.endurance26Weeks
    readonly property var _recentActivities: GarminState.recentActivities
    readonly property bool _fetching: GarminState.fetching

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
    readonly property real _chartEnduranceMin: 4500
    readonly property real _chartEnduranceMax: 9000

    readonly property int _hrvToday: _hrv28Days.length > 0 ? _hrv28Days[_hrv28Days.length - 1].hrv : 0
    readonly property string _hrvStatusLabel: {
        const map = {
            "BALANCED": "Balanced",
            "UNBALANCED": "Unbalanced",
            "POOR": "Poor",
            "LOW": "Low"
        };
        return map[_hrvStatus] || _hrvStatus;
    }
    readonly property real _chartHrvMin: {
        let min = Infinity;
        for (const item of _hrv28Days)
            if (item.hrv < min)
                min = item.hrv;
        return isFinite(min) ? Math.max(0, min - 5) : 0;
    }
    readonly property real _chartHrvMax: _seriesMax(_hrv28Days, "hrv", 60) + 5

    readonly property string _enduranceTierLabel: {
        if (_enduranceScore <= 0)
            return "";
        const tiers = ["Untrained", "Recreational", "Intermediate", "Trained", "Well Trained", "Expert", "Superior", "Elite"];
        return tiers[Math.max(0, Math.min(7, _enduranceClassification))];
    }

    function _activityLabel(typeKey) {
        const map = {
            "running": "Run",
            "cycling": "Ride",
            "swimming": "Swim",
            "walking": "Walk",
            "hiking": "Hike",
            "strength_training": "Lift",
            "yoga": "Yoga",
            "indoor_cycling": "Ride",
            "treadmill_running": "TM",
            "trail_running": "Trail",
            "open_water_swimming": "OWS",
            "elliptical": "Elip",
            "fitness_equipment": "Gym"
        };
        const key = typeKey || "";
        if (map[key])
            return map[key];
        if (key.length === 0)
            return "—";
        return key.charAt(0).toUpperCase() + key.slice(1, 4);
    }

    function _shortDate(isoDate) {
        if (!isoDate)
            return "";
        const parts = isoDate.split("-");
        const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
        return months[parseInt(parts[1]) - 1] + " " + parseInt(parts[2]);
    }

    function _formatDistance(meters) {
        const m = Number(meters);
        if (!isFinite(m) || m <= 0)
            return "—";
        if (m >= 1000)
            return (m / 1000).toFixed(1) + " km";
        return Math.round(m) + " m";
    }

    function _formatPace(metersPerSecond) {
        const mps = Number(metersPerSecond);
        if (!isFinite(mps) || mps <= 0)
            return "";
        const secsPerKm = 1000 / mps;
        const m = Math.floor(secsPerKm / 60);
        const s = Math.round(secsPerKm % 60);
        return m + ":" + String(s).padStart(2, "0") + "/km";
    }

    function _formatElevation(gain, loss) {
        const g = Number(gain) || 0;
        const l = Number(loss) || 0;
        const parts = [];
        if (g > 0)
            parts.push("↑" + Math.round(g) + "m");
        if (l > 0)
            parts.push("↓" + Math.round(l) + "m");
        return parts.join(" ");
    }

    onVisibleChanged: {
        if (!visible)
            return;
        GarminState.ensureStarted();
        if (!GarminState.didInitialFullFetch)
            GarminState.scheduleStartupFullFetch();
    }

    Column {
        id: mainColumn
        width: parent.width
        spacing: 8

        Row {
            width: parent.width
            height: 88
            spacing: 8

            Item {
                width: (parent.width - 8) * 2 / 3
                height: parent.height

                Column {
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
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

                        AccentText {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root._enduranceScore > 0 ? String(root._enduranceScore) : ""
                            fontFamily: Theme.fontFamily
                            fontPixelSize: 10
                            fontBold: true
                            color: root._accentColor
                            visible: text !== ""
                            radius: 6
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
                            if (!data || data.length < 2)
                                return;

                            var n = data.length;
                            var hpad = 4;
                            var vpad = 4;
                            var bpad = 14;
                            var r = 6;
                            var range = chartMax - chartMin;

                            function xAt(i) {
                                return hpad + i * (width - 2 * hpad) / (n - 1);
                            }
                            function yAt(s) {
                                return vpad + (height - vpad - bpad) * (1 - (s - chartMin) / range);
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

                            var enduranceLines = [
                                {
                                    score: 8900,
                                    c: "rgba(236,72,153,0.25)"
                                },
                                {
                                    score: 8450,
                                    c: "rgba(147,51,234,0.25)"
                                },
                                {
                                    score: 7700,
                                    c: "rgba(59,130,246,0.25)"
                                },
                                {
                                    score: 6950,
                                    c: "rgba(34,197,94,0.25)"
                                },
                                {
                                    score: 6200,
                                    c: "rgba(234,179,8,0.25)"
                                },
                                {
                                    score: 5450,
                                    c: "rgba(249,115,22,0.25)"
                                },
                                {
                                    score: 4500,
                                    c: "rgba(239,68,68,0.25)"
                                },
                            ];
                            for (var t = 0; t < enduranceLines.length; t++) {
                                var ey = yAt(enduranceLines[t].score);
                                ctx.beginPath();
                                ctx.moveTo(hpad, ey);
                                ctx.lineTo(width - hpad, ey);
                                ctx.strokeStyle = enduranceLines[t].c;
                                ctx.lineWidth = 1;
                                ctx.stroke();
                            }

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

                            for (var j = 0; j < n - 1; j++) {
                                ctx.beginPath();
                                ctx.arc(xAt(j), yAt(data[j].score), 1.5, 0, Math.PI * 2);
                                ctx.fillStyle = col;
                                ctx.globalAlpha = 0.55;
                                ctx.fill();
                                ctx.globalAlpha = 1.0;
                            }

                            ctx.beginPath();
                            ctx.arc(xAt(n - 1), yAt(data[n - 1].score), 3.5, 0, Math.PI * 2);
                            ctx.fillStyle = col;
                            ctx.fill();
                            ctx.beginPath();
                            ctx.arc(xAt(n - 1), yAt(data[n - 1].score), 1.5, 0, Math.PI * 2);
                            ctx.fillStyle = "rgba(255,255,255,0.9)";
                            ctx.fill();

                            var monthAbbr = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                            ctx.font = "7px sans-serif";
                            ctx.textAlign = "center";
                            ctx.fillStyle = "rgba(255,255,255,0.38)";
                            var labelIdxs = [0];
                            for (var k = 7; k < n; k += 7)
                                labelIdxs.push(k);
                            if (labelIdxs[labelIdxs.length - 1] !== n - 1)
                                labelIdxs.push(n - 1);
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

            Item {
                width: (parent.width - 8) / 3
                height: parent.height

                Column {
                    id: metricsColumn
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    anchors.left: parent.left
                    anchors.leftMargin: 4
                    anchors.right: parent.right
                    anchors.rightMargin: 4
                    spacing: 2

                    Item {
                        width: parent.width
                        height: 20

                        Item {
                            id: statusSpinner
                            width: 16
                            height: 16
                            anchors.right: parent.right
                            anchors.top: parent.top
                            visible: root._fetching

                            Canvas {
                                id: statusSpinnerCanvas
                                anchors.fill: parent
                                onVisibleChanged: requestPaint()
                                onWidthChanged: requestPaint()
                                onHeightChanged: requestPaint()
                                onPaint: {
                                    var ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    ctx.beginPath();
                                    ctx.arc(width / 2, height / 2, 6.3, 0, Math.PI * 1.5);
                                    ctx.strokeStyle = String(root._accentColor);
                                    ctx.lineWidth = 2;
                                    ctx.lineCap = "round";
                                    ctx.stroke();
                                }
                            }

                            onVisibleChanged: {
                                if (visible)
                                    statusSpinnerCanvas.requestPaint();
                            }

                            RotationAnimator {
                                target: statusSpinner
                                from: 0
                                to: 360
                                duration: 1080
                                loops: Animation.Infinite
                                running: statusSpinner.visible
                            }
                        }
                    }

                    Repeater {
                        model: [
                            {
                                label: "VO2 max",
                                value: root._vo2Max > 0 ? String(root._vo2Max) : ""
                            },
                            {
                                label: "Resting HR",
                                value: root._restingHeartRate > 0 ? root._restingHeartRate + " bpm" : ""
                            },
                            {
                                label: "Marathon",
                                value: root._marathonPredictionSeconds > 0 ? root._formatRaceTime(root._marathonPredictionSeconds) : ""
                            }
                        ]

                        delegate: Item {
                            width: parent.width
                            height: 15

                            Text {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.letterSpacing: 0.8
                                color: root._mutedColor
                                elide: Text.ElideRight
                            }

                            Text {
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.value
                                font.family: Theme.fontFamily
                                font.pixelSize: 10
                                font.bold: true
                                color: root._textColor
                                elide: Text.ElideRight
                                visible: text !== ""
                            }
                        }
                    }
                }
            }
        }

        Row {
            width: parent.width
            height: 90
            spacing: 8

            Item {
                width: (parent.width - 8) * 2 / 3
                height: parent.height

                Column {
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    spacing: 6

                    Text {
                        width: parent.width
                        height: 12
                        text: "Recent"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 0.8
                        color: root._mutedColor
                        verticalAlignment: Text.AlignVCenter
                    }

                    Column {
                        width: parent.width
                        spacing: 4
                        visible: root._recentActivities.length > 0

                        Repeater {
                            model: root._recentActivities

                            delegate: Item {
                                width: parent.width
                                height: 16

                                AccentText {
                                    id: aType
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root._activityLabel(modelData.type)
                                    fontFamily: Theme.fontFamily
                                    fontPixelSize: 10
                                    fontBold: true
                                    color: root._textColor
                                    width: 30
                                    elide: Text.ElideRight
                                    radius: 6
                                    paddingX: 3
                                }

                                Text {
                                    id: aDist
                                    anchors.left: aType.right
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root._formatDistance(modelData.distance)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 10
                                    color: root._textColor
                                    width: 52
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideLeft
                                }

                                Text {
                                    id: aDur
                                    anchors.left: aDist.right
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root._formatDuration(modelData.duration)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    color: root._mutedColor
                                    width: 36
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideLeft
                                }

                                Text {
                                    id: aPace
                                    anchors.left: aDur.right
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root._formatPace(modelData.averageSpeed)
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    color: root._mutedColor
                                    width: 42
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideLeft
                                    visible: text !== ""
                                }

                                Text {
                                    id: aGain
                                    anchors.left: aPace.visible ? aPace.right : aDur.right
                                    anchors.leftMargin: 4
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.elevationGain > 0 ? "↑" + Math.round(modelData.elevationGain) + "m" : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    color: root._mutedColor
                                    width: 40
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideLeft
                                }

                                Text {
                                    anchors.left: aGain.right
                                    anchors.leftMargin: 2
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.elevationLoss > 0 ? "↓" + Math.round(modelData.elevationLoss) + "m" : ""
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 9
                                    color: root._mutedColor
                                    width: 45
                                    horizontalAlignment: Text.AlignRight
                                    elide: Text.ElideLeft
                                }
                            }
                        }
                    }
                }
            }

            Item {
                width: (parent.width - 8) / 3
                height: parent.height

                Column {
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
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

                        AccentText {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                const last = root._steps7Days[root._steps7Days.length - 1];
                                return last && last.steps > 0 ? last.steps.toLocaleString() : "";
                            }
                            fontFamily: Theme.fontFamily
                            fontPixelSize: 10
                            fontBold: true
                            color: root._textColor
                            visible: text !== ""
                            radius: 6
                        }
                    }

                    Item {
                        width: parent.width
                        height: 62

                        Row {
                            id: stepsChartRow
                            anchors.fill: parent
                            spacing: 2

                            readonly property real goalSteps: 10000
                            readonly property color goalLineColor: Qt.rgba(34 / 255, 197 / 255, 94 / 255, 0.25)

                            Repeater {
                                model: root._steps7Days

                                delegate: Item {
                                    width: (stepsChartRow.width - stepsChartRow.spacing * 6) / 7
                                    height: stepsChartRow.height

                                    Rectangle {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        anchors.bottom: parent.bottom
                                        width: Math.max(2, parent.width)
                                        height: Math.max(2, parent.height * (modelData.steps / Math.max(1, root._chartStepsMax)))
                                        radius: 2
                                        color: root._accentColor
                                        opacity: 0.75
                                    }
                                }
                            }
                        }

                        Item {
                            anchors.fill: parent

                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                y: Math.max(0, Math.min(parent.height - 1, parent.height - (parent.height * (stepsChartRow.goalSteps / Math.max(1, root._chartStepsMax)))))
                                height: 1
                                color: stepsChartRow.goalLineColor
                            }
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
                        minValue: 21600,
                        maxValue: Math.max(root._chartSleepMax, 32400)
                    },
                    {
                        label: "Sleep Score",
                        field: "sleepScore",
                        minValue: 50,
                        maxValue: 100
                    }
                ]

                delegate: Item {
                    id: chartCard
                    property string chartLabel: modelData.label
                    property string chartField: modelData.field
                    property real chartMinValue: modelData.minValue
                    property real chartMaxValue: modelData.maxValue
                    width: (chartsRow.width - chartsRow.spacing) / 2
                    height: chartsRow.height

                    Column {
                        anchors.fill: parent
                        anchors.topMargin: 8
                        anchors.bottomMargin: 8
                        anchors.leftMargin: 4
                        anchors.rightMargin: 4
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

                            AccentText {
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
                                fontFamily: Theme.fontFamily
                                fontPixelSize: 10
                                fontBold: true
                                color: root._textColor
                                visible: text !== ""
                                radius: 6
                            }
                        }

                        Canvas {
                            width: parent.width
                            height: 70

                            property string field: chartCard.chartField
                            property var chartData: root._weekChart
                            property real chartMin: chartCard.chartMinValue
                            property real chartMax: chartCard.chartMaxValue

                            onChartDataChanged: requestPaint()
                            onChartMinChanged: requestPaint()
                            onChartMaxChanged: requestPaint()

                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.clearRect(0, 0, width, height);
                                var data = chartData;
                                if (!data || data.length < 2)
                                    return;

                                var n = data.length;
                                var hpad = 4;
                                var vpad = 4;
                                var bpad = 14;
                                var r = 6;
                                var minVal = chartMin;
                                var maxVal = chartMax > minVal ? chartMax : minVal + 1;
                                var range = maxVal - minVal;

                                var values = [];
                                for (var vi = 0; vi < n; vi++)
                                    values.push(Number(data[vi][field]) || 0);

                                function xAt(i) {
                                    return hpad + i * (width - 2 * hpad) / (n - 1);
                                }
                                function yAt(v) {
                                    return vpad + (height - vpad - bpad) * (1 - (v - minVal) / range);
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

                                var threshLines = [];
                                if (field === "stress") {
                                    threshLines = [
                                        {
                                            v: 100,
                                            c: "rgba(34,197,94,0.25)"
                                        },
                                        {
                                            v: 75,
                                            c: "rgba(249,115,22,0.25)"
                                        },
                                        {
                                            v: 50,
                                            c: "rgba(234,179,8,0.25)"
                                        },
                                        {
                                            v: 25,
                                            c: "rgba(34,197,94,0.25)"
                                        },
                                    ];
                                } else if (field === "sleepScore") {
                                    threshLines = [
                                        {
                                            v: 100,
                                            c: "rgba(239,68,68,0.25)"
                                        },
                                        {
                                            v: 80,
                                            c: "rgba(34,197,94,0.25)"
                                        },
                                        {
                                            v: 70,
                                            c: "rgba(234,179,8,0.25)"
                                        },
                                        {
                                            v: 60,
                                            c: "rgba(249,115,22,0.25)"
                                        },
                                        {
                                            v: 50,
                                            c: "rgba(239,68,68,0.25)"
                                        },
                                    ];
                                } else {
                                    threshLines = [
                                        {
                                            v: 32400,
                                            c: "rgba(34,197,94,0.25)"
                                        },
                                        {
                                            v: 28800,
                                            c: "rgba(34,197,94,0.25)"
                                        },
                                        {
                                            v: 27000,
                                            c: "rgba(234,179,8,0.25)"
                                        },
                                        {
                                            v: 25200,
                                            c: "rgba(249,115,22,0.25)"
                                        },
                                        {
                                            v: 21600,
                                            c: "rgba(239,68,68,0.25)"
                                        },
                                    ];
                                }
                                for (var tli = 0; tli < threshLines.length; tli++) {
                                    var ty = yAt(threshLines[tli].v);
                                    ctx.beginPath();
                                    ctx.moveTo(hpad, ty);
                                    ctx.lineTo(width - hpad, ty);
                                    ctx.strokeStyle = threshLines[tli].c;
                                    ctx.lineWidth = 1;
                                    ctx.stroke();
                                }

                                var col = String(root._accentColor);

                                ctx.beginPath();
                                ctx.moveTo(xAt(0), yAt(values[0]));
                                for (var i = 1; i < n; i++)
                                    ctx.lineTo(xAt(i), yAt(values[i]));
                                ctx.strokeStyle = col;
                                ctx.lineWidth = 1.5;
                                ctx.lineJoin = "round";
                                ctx.globalAlpha = 0.75;
                                ctx.stroke();
                                ctx.globalAlpha = 1.0;

                                for (var j = 0; j < n - 1; j++) {
                                    ctx.beginPath();
                                    ctx.arc(xAt(j), yAt(values[j]), 1.5, 0, Math.PI * 2);
                                    ctx.fillStyle = col;
                                    ctx.globalAlpha = 0.55;
                                    ctx.fill();
                                    ctx.globalAlpha = 1.0;
                                }

                                ctx.beginPath();
                                ctx.arc(xAt(n - 1), yAt(values[n - 1]), 3.5, 0, Math.PI * 2);
                                ctx.fillStyle = col;
                                ctx.fill();
                                ctx.beginPath();
                                ctx.arc(xAt(n - 1), yAt(values[n - 1]), 1.5, 0, Math.PI * 2);
                                ctx.fillStyle = "rgba(255,255,255,0.9)";
                                ctx.fill();

                                ctx.font = "7px sans-serif";
                                ctx.textAlign = "center";
                                ctx.fillStyle = "rgba(255,255,255,0.38)";
                                for (var k = 0; k < n; k++)
                                    ctx.fillText(data[k].label, xAt(k), height - 3);

                                ctx.restore();
                            }
                        }
                    }
                }
            }
        }

        Row {
            width: parent.width
            height: 88
            spacing: 8

            Item {
                width: (parent.width - 8) / 3
                height: parent.height

                Column {
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 12

                        Text {
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Stress"
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.letterSpacing: 0.8
                            color: root._mutedColor
                        }

                        AccentText {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root._stressToday > 0 ? String(root._stressToday) : ""
                            fontFamily: Theme.fontFamily
                            fontPixelSize: 10
                            fontBold: true
                            color: root._textColor
                            visible: text !== ""
                            radius: 6
                        }
                    }

                    Canvas {
                        width: parent.width
                        height: 62

                        property string field: "stress"
                        property var chartData: root._weekChart
                        property real chartMin: 0
                        property real chartMax: 100

                        onChartDataChanged: requestPaint()

                        onPaint: {
                            var ctx = getContext("2d");
                            ctx.clearRect(0, 0, width, height);
                            var data = chartData;
                            if (!data || data.length < 2)
                                return;

                            var n = data.length;
                            var hpad = 4, vpad = 4, bpad = 14, r = 6;
                            var minVal = 0, maxVal = 100, range = 100;

                            var values = [];
                            for (var vi = 0; vi < n; vi++)
                                values.push(Number(data[vi]["stress"]) || 0);

                            function xAt(i) {
                                return hpad + i * (width - 2 * hpad) / (n - 1);
                            }
                            function yAt(v) {
                                return vpad + (height - vpad - bpad) * (1 - (v - minVal) / range);
                            }
                            function gradPos(v) {
                                return Math.max(0, Math.min(1, yAt(v) / height));
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

                            var stressLines = [
                                {
                                    v: 100,
                                    c: "rgba(34,197,94,0.25)"
                                },
                                {
                                    v: 75,
                                    c: "rgba(249,115,22,0.25)"
                                },
                                {
                                    v: 50,
                                    c: "rgba(234,179,8,0.25)"
                                },
                                {
                                    v: 25,
                                    c: "rgba(34,197,94,0.25)"
                                },
                            ];
                            for (var sli = 0; sli < stressLines.length; sli++) {
                                var sly = yAt(stressLines[sli].v);
                                ctx.beginPath();
                                ctx.moveTo(hpad, sly);
                                ctx.lineTo(width - hpad, sly);
                                ctx.strokeStyle = stressLines[sli].c;
                                ctx.lineWidth = 1;
                                ctx.stroke();
                            }

                            var col = String(root._accentColor);

                            ctx.beginPath();
                            ctx.moveTo(xAt(0), yAt(values[0]));
                            for (var i = 1; i < n; i++)
                                ctx.lineTo(xAt(i), yAt(values[i]));
                            ctx.strokeStyle = col;
                            ctx.lineWidth = 1.5;
                            ctx.lineJoin = "round";
                            ctx.globalAlpha = 0.75;
                            ctx.stroke();
                            ctx.globalAlpha = 1.0;

                            for (var j = 0; j < n - 1; j++) {
                                ctx.beginPath();
                                ctx.arc(xAt(j), yAt(values[j]), 1.5, 0, Math.PI * 2);
                                ctx.fillStyle = col;
                                ctx.globalAlpha = 0.55;
                                ctx.fill();
                                ctx.globalAlpha = 1.0;
                            }

                            ctx.beginPath();
                            ctx.arc(xAt(n - 1), yAt(values[n - 1]), 3.5, 0, Math.PI * 2);
                            ctx.fillStyle = col;
                            ctx.fill();
                            ctx.beginPath();
                            ctx.arc(xAt(n - 1), yAt(values[n - 1]), 1.5, 0, Math.PI * 2);
                            ctx.fillStyle = "rgba(255,255,255,0.9)";
                            ctx.fill();

                            ctx.font = "7px sans-serif";
                            ctx.textAlign = "center";
                            ctx.fillStyle = "rgba(255,255,255,0.38)";
                            for (var k = 0; k < n; k++)
                                ctx.fillText(data[k].label, xAt(k), height - 3);

                            ctx.restore();
                        }
                    }
                }
            }

            Item {
                width: (parent.width - 8) * 2 / 3
                height: parent.height

                Column {
                    anchors.fill: parent
                    anchors.topMargin: 8
                    anchors.bottomMargin: 8
                    anchors.leftMargin: 4
                    anchors.rightMargin: 4
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

                        AccentText {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: root._hrvToday > 0 ? String(root._hrvToday) : ""
                            fontFamily: Theme.fontFamily
                            fontPixelSize: 10
                            fontBold: true
                            color: root._textColor
                            visible: text !== ""
                            radius: 6
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
                            if (!data || data.length < 2)
                                return;

                            var n = data.length;
                            var hpad = 4;
                            var vpad = 4;
                            var bpad = 14;
                            var r = 6;
                            var range = chartMax - chartMin;
                            if (range <= 0)
                                return;

                            function xAt(i) {
                                return hpad + i * (width - 2 * hpad) / (n - 1);
                            }
                            function yAt(s) {
                                return vpad + (height - vpad - bpad) * (1 - (s - chartMin) / range);
                            }
                            function posAt(s) {
                                return Math.max(0, Math.min(1, (vpad + (height - vpad - bpad) * (1 - (s - chartMin) / range)) / height));
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

                            var bLow = baselineLow > 0 ? baselineLow : chartMin + range * 0.35;
                            var bHigh = baselineHigh > 0 ? baselineHigh : chartMin + range * 0.65;
                            var aboveStop = bHigh + (chartMax - bHigh) * 0.5;
                            var belowStop = bLow - (bLow - chartMin) * 0.5;

                            var hrvLines = [
                                {
                                    v: chartMax,
                                    c: "rgba(249,115,22,0.25)"
                                },
                                {
                                    v: aboveStop,
                                    c: "rgba(249,115,22,0.25)"
                                },
                                {
                                    v: bHigh,
                                    c: "rgba(34,197,94,0.25)"
                                },
                                {
                                    v: bLow,
                                    c: "rgba(34,197,94,0.25)"
                                },
                                {
                                    v: belowStop,
                                    c: "rgba(249,115,22,0.25)"
                                },
                            ];
                            for (var hli = 0; hli < hrvLines.length; hli++) {
                                var hly = yAt(hrvLines[hli].v);
                                ctx.beginPath();
                                ctx.moveTo(hpad, hly);
                                ctx.lineTo(width - hpad, hly);
                                ctx.strokeStyle = hrvLines[hli].c;
                                ctx.lineWidth = 1;
                                ctx.stroke();
                            }

                            if (baselineLow > chartMin && baselineHigh > chartMin) {
                                ctx.fillStyle = "rgba(34,197,94,0.10)";
                                ctx.fillRect(hpad, yAt(baselineHigh), width - 2 * hpad, yAt(baselineLow) - yAt(baselineHigh));
                            }

                            var col = String(root._accentColor);

                            ctx.beginPath();
                            ctx.moveTo(xAt(0), yAt(data[0].hrv));
                            for (var i = 1; i < n; i++)
                                ctx.lineTo(xAt(i), yAt(data[i].hrv));
                            ctx.strokeStyle = col;
                            ctx.lineWidth = 1;
                            ctx.lineJoin = "round";
                            ctx.globalAlpha = 0.35;
                            ctx.stroke();
                            ctx.globalAlpha = 1.0;

                            var rolling = [];
                            for (var ri = 0; ri < n; ri++) {
                                var sum = 0, cnt = 0;
                                for (var rj = Math.max(0, ri - 6); rj <= ri; rj++) {
                                    sum += data[rj].hrv;
                                    cnt++;
                                }
                                rolling.push(sum / cnt);
                            }
                            ctx.beginPath();
                            ctx.moveTo(xAt(0), yAt(rolling[0]));
                            for (var ri2 = 1; ri2 < n; ri2++)
                                ctx.lineTo(xAt(ri2), yAt(rolling[ri2]));
                            ctx.strokeStyle = col;
                            ctx.lineWidth = 2;
                            ctx.lineJoin = "round";
                            ctx.globalAlpha = 0.85;
                            ctx.stroke();
                            ctx.globalAlpha = 1.0;

                            for (var j = 0; j < n - 1; j++) {
                                ctx.beginPath();
                                ctx.arc(xAt(j), yAt(data[j].hrv), 1.5, 0, Math.PI * 2);
                                ctx.fillStyle = col;
                                ctx.globalAlpha = 0.55;
                                ctx.fill();
                                ctx.globalAlpha = 1.0;
                            }

                            ctx.beginPath();
                            ctx.arc(xAt(n - 1), yAt(rolling[n - 1]), 3.5, 0, Math.PI * 2);
                            ctx.fillStyle = col;
                            ctx.fill();
                            ctx.beginPath();
                            ctx.arc(xAt(n - 1), yAt(rolling[n - 1]), 1.5, 0, Math.PI * 2);
                            ctx.fillStyle = "rgba(255,255,255,0.9)";
                            ctx.fill();

                            var monthAbbr = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
                            ctx.font = "7px sans-serif";
                            ctx.textAlign = "center";
                            ctx.fillStyle = "rgba(255,255,255,0.38)";
                            var labelIdxs = [0];
                            for (var k = 7; k < n; k += 7)
                                labelIdxs.push(k);
                            if (labelIdxs[labelIdxs.length - 1] !== n - 1)
                                labelIdxs.push(n - 1);
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
        }
    }
}
