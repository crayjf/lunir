import QtQuick 2.15
import Quickshell
import Quickshell.Io
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")

    readonly property var _cfg:      moduleConfig ? (moduleConfig.props || {}) : {}
    readonly property string _email:    _cfg.email    || ""
    readonly property string _password: _cfg.password || ""
    readonly property int _intervalMin: _cfg.refreshInterval || 10

    property int    _steps:    0
    property int    _goal:     10000
    property real   _distance: 0
    property int    _kcal:     0
    property bool   _fetching: false
    property string _status:   "loading…"

    readonly property string _scriptPath: Quickshell.shellPath("scripts/garmin_fetch.py")
    readonly property string _tokenStore: Quickshell.dataPath("garmin-tokens")

    // ── Fetch ─────────────────────────────────────────────────────────────────
    Process {
        id: fetchProc
        command: ["python3", root._scriptPath, root._email, root._password, root._tokenStore]
        running: false
        stdout: StdioCollector { id: fetchStdio }
        onExited: {
            root._fetching = false
            refreshBtn.buttonEnabled = true
            // Take only the last non-empty line — StdioCollector accumulates across runs
            const lines = fetchStdio.text.trim().split("\n").filter(l => l.trim() !== "")
            const lastLine = lines.length > 0 ? lines[lines.length - 1] : ""
            try {
                const data = JSON.parse(lastLine)
                if (data.error) {
                    if (data.error === "no_tokens") {
                        root._status = "setup needed — run garmin_setup.py"
                        refreshTimer.interval = 30000
                    } else if (data.error.startsWith("rate_limited")) {
                        root._status = "rate limited — retry in 60 min"
                        refreshTimer.interval = 3600000
                    } else {
                        root._status = data.error
                        refreshTimer.interval = root._intervalMin * 60000
                    }
                } else {
                    root._steps    = data.steps        || 0
                    root._goal     = data.goal         || 10000
                    root._distance = data.distance_km  || 0
                    root._kcal     = data.active_kcal  || 0
                    root._status   = ""
                    refreshTimer.interval = root._intervalMin * 60000
                }
            } catch (e) {
                root._status = "parse error: " + lastLine.substring(0, 60)
                refreshTimer.interval = root._intervalMin * 60000
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
        if (_fetching || !_email || !_password) return
        _fetching = true
        refreshBtn.buttonEnabled = false
        _status = "fetching…"
        fetchProc.running = true
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors { fill: parent; margins: 10 }
        spacing: 8

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "STEPS TODAY"
            font.family: Theme.fontFamily
            font.pixelSize: 9; font.letterSpacing: 2
            color: root._accentColor
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root._steps > 0 ? root._steps.toLocaleString() : "—"
            font.family: Theme.fontFamily
            font.pixelSize: 36
            color: root._textColor
        }

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root._status !== ""
                ? root._status
                : "of " + root._goal.toLocaleString() + " goal  ·  " + Math.round(root._steps / Math.max(1, root._goal) * 100) + "%"
            font.family: Theme.fontFamily
            font.pixelSize: 10
            color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.6)
        }

        // Progress bar
        Rectangle {
            width: parent.width; height: 6; radius: 3
            color: Qt.rgba(1,1,1,0.10)
            Rectangle {
                width: parent.width * Math.min(1, root._steps / Math.max(1, root._goal))
                height: parent.height; radius: parent.radius
                color: root._accentColor
                Behavior on width { NumberAnimation { duration: 400 } }
            }
        }

        // Stats row
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 24
            Text {
                text: root._distance > 0 ? root._distance + " km" : "—"
                font.family: Theme.fontFamily
                font.pixelSize: 10; color: root._textColor
            }
            Text {
                text: root._kcal > 0 ? root._kcal + " kcal" : "—"
                font.family: Theme.fontFamily
                font.pixelSize: 10; color: root._textColor
            }
        }

        // Refresh button
        Rectangle {
            id: refreshBtn
            property bool buttonEnabled: true
            anchors.horizontalCenter: parent.horizontalCenter
            width: 80; height: 24; radius: 3
            color: refreshMA.containsMouse ? Qt.rgba(1,1,1,0.12) : Qt.rgba(1,1,1,0.06)
            opacity: buttonEnabled ? 1.0 : 0.4
            Text { anchors.centerIn: parent; text: "REFRESH"; font.family: Theme.fontFamily; font.pixelSize: 9; font.letterSpacing: 1; color: root._textColor }
            MouseArea {
                id: refreshMA; anchors.fill: parent; hoverEnabled: true
                onClicked: { if (refreshBtn.buttonEnabled) root._fetch() }
            }
        }
    }
}
