import QtQuick 2.15
import QtQuick.Shapes 1.15
import Quickshell
import Quickshell.Io
import "../lib"
import "../lib/ShellUtils.js" as ShellUtils

Item {
    id: root
    property var moduleConfig: null
    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", Config.theme.accent)
    readonly property color _mutedText: Theme.textMuted

    property var   _pool: []
    property int   _idx: 0
    property bool  _fetching: false
    property real  _lastFetchMs: 0
    property string _todayKey: ""

    readonly property var _FALLBACK: [
        { text: "Simplicity is the ultimate sophistication.", author: "Leonardo da Vinci" },
        { text: "In the middle of every difficulty lies opportunity.", author: "Albert Einstein" },
        { text: "Be the change that you wish to see in the world.", author: "Mahatma Gandhi" },
        { text: "Life is either a daring adventure or nothing at all.", author: "Helen Keller" },
        { text: "The only way to do great work is to love what you do.", author: "Steve Jobs" },
    ]

    property string quoteText:  "…"
    property string authorText: ""
    property string authorLeadText: ""
    property string authorLastNameText: ""
    property bool _initialized: false
    readonly property string _cachePath: Quickshell.dataPath("quote-cache.json")
    readonly property real _fixedContentHeight: quoteMinMeasure.paintedHeight + contentColumn.spacing + authorMinMeasure.implicitHeight

    function _splitAuthor(author) {
        const plain = String(author || "").trim()
        if (!plain)
            return {
                lead: "",
                last: ""
            }
        const parts = plain.split(/\s+/)
        if (parts.length === 1)
            return {
                lead: "",
                last: parts[0]
            }
        return {
            lead: "— " + parts.slice(0, -1).join(" "),
            last: parts[parts.length - 1]
        }
    }

    function _beginLoading() {
        if (_fetching)
            return false
        _fetching = true
        return true
    }

    // ── Cache ─────────────────────────────────────────────────────────────────
    Process {
        id: readCacheProc
        command: ["cat", root._cachePath]
        running: false
        stdout: StdioCollector { id: readCacheStdio }
        onExited: (code) => {
            if (code === 0) {
                try {
                    const c = JSON.parse(readCacheStdio.text)
                    const today = new Date().toISOString().slice(0, 10)
                    if (c.date === today && Array.isArray(c.quotes) && c.quotes.length > 0) {
                        root._pool = c.quotes
                        root._idx  = Math.floor(Math.random() * c.quotes.length)
                        root._showCurrent()
                        return
                    }
                } catch (_) {}
            }
            root._fetchToday()
        }
    }

    Process {
        id: fetchProc
        property string endpoint: "today"
        command: ["curl", "-s", "--max-time", "6",
                  "https://zenquotes.io/api/" + endpoint]
        running: false

        stdout: StdioCollector { id: fetchStdio }

        onExited: {
            root._fetching = false
            root._lastFetchMs = Date.now()
            try {
                const data = JSON.parse(fetchStdio.text.trim())
                const quotes = data
                    .filter(function(q) { return q.q && q.a && !q.a.includes("zenquotes") })
                    .map(function(q) { return { text: q.q, author: q.a } })
                if (quotes.length > 0) {
                    root._pool = quotes
                    if (fetchProc.endpoint === "today")
                        root._saveCache(quotes)
                } else {
                    root._pool = root._FALLBACK
                }
            } catch (_) { root._pool = root._FALLBACK }
            if (root._pool.length > 0 && (root.quoteText === "…" || fetchProc.endpoint === "random")) {
                root._idx = Math.floor(Math.random() * root._pool.length)
                root._showCurrent()
            }
        }
    }

    Process {
        id: saveCacheProc
        property string content: ""
        command: ShellUtils.writeFileCommand(root._cachePath, saveCacheProc.content)
        running: false
    }

    function _saveCache(quotes) {
        const today = new Date().toISOString().slice(0, 10)
        saveCacheProc.content = JSON.stringify({ date: today, quotes: quotes })
        saveCacheProc.running = true
    }

    function _fetchToday() {
        if (!_beginLoading()) return
        fetchProc.endpoint = "today"
        fetchProc.running = true
    }

    function _fetchRandom() {
        if (!_beginLoading()) return
        fetchProc.endpoint = "random"
        fetchProc.running = true
    }

    function _requestNewQuote() {
        if (_fetching) return
        _ensureInitialized()
        root._pool = []
        root._idx = 0
        root._fetchRandom()
    }

    function _showCurrent() {
        if (_pool.length === 0) return
        const q = _pool[_idx % _pool.length]
        quoteText  = "\"" + q.text + "\""
        authorText = "— " + q.author
        const authorParts = root._splitAuthor(q.author)
        authorLeadText = authorParts.lead
        authorLastNameText = authorParts.last
    }

    function _scheduleMidnightReset() {
        const now = new Date()
        const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
        midnightTimer.interval = midnight.getTime() - now.getTime()
        midnightTimer.start()
    }

    function _ensureInitialized() {
        if (_initialized)
            return
        _initialized = true
        readCacheProc.running = true
        _scheduleMidnightReset()
    }

    // Midnight reset
    Timer {
        id: midnightTimer
        repeat: false
        onTriggered: {
            root._pool = []
            root._idx  = 0
            root._fetchToday()
            root._scheduleMidnightReset()
        }
    }

    onVisibleChanged: if (visible)
        _ensureInitialized()
    Component.onCompleted: if (visible)
        _ensureInitialized()

    readonly property real preferredHeight: root._fixedContentHeight + 20
    implicitHeight: preferredHeight

    // ── UI ────────────────────────────────────────────────────────────────────
    Item {
        id: quoteColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: root._fixedContentHeight

        Column {
            id: contentColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 10
            opacity: root._fetching ? 0.0 : 1.0

            Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

            Text {
                id: quoteLabel
                text: root.quoteText
                font.family: Theme.fontFamily
                font.pixelSize: 13
                color: root._textColor
                wrapMode: Text.WordWrap
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
            }

            Item {
                id: authorBlock
                width: parent.width
                height: authorRow.visible ? authorRow.implicitHeight : 0

                Row {
                    id: authorRow
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 4
                    visible: root.authorLastNameText !== ""

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.authorLeadText !== "" ? root.authorLeadText : "—"
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        font.letterSpacing: 1
                        color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.6)
                    }

                    AccentText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.authorLastNameText
                        fontFamily: Theme.fontFamily
                        fontPixelSize: 11
                        fontLetterSpacing: 1
                        color: root._textColor
                        radius: 6
                        paddingX: 4
                        paddingY: 1
                    }
                }
            }
        }

        Text {
            id: quoteMinMeasure
            visible: false
            width: contentColumn.width
            text: "\"Line one\nLine two\nLine three\""
            font.family: Theme.fontFamily
            font.pixelSize: 13
            wrapMode: Text.WordWrap
        }

        Text {
            id: authorMinMeasure
            visible: false
            text: "Ag"
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 1
        }

        Item {
            id: loadingWrap
            anchors.fill: parent
            opacity: root._fetching ? 1.0 : 0.0

            Behavior on opacity { NumberAnimation { duration: 170; easing.type: Easing.OutCubic } }

            Text {
                anchors.centerIn: parent
                visible: false
            }

            Item {
                id: loadingIcon
                anchors.centerIn: parent
                width: 60
                height: 60
                opacity: 0.95

                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: 1000
                    loops: Animation.Infinite
                    running: root._fetching
                }

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: Qt.rgba(root._mutedText.r, root._mutedText.g, root._mutedText.b, 0.22)
                        strokeWidth: 4
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: loadingIcon.width / 2
                            centerY: loadingIcon.height / 2
                            radiusX: 18
                            radiusY: 18
                            startAngle: 0
                            sweepAngle: 360
                        }
                    }

                    ShapePath {
                        strokeColor: root._accentColor
                        strokeWidth: 5
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            centerX: loadingIcon.width / 2
                            centerY: loadingIcon.height / 2
                            radiusX: 18
                            radiusY: 18
                            startAngle: -90
                            sweepAngle: 110
                        }
                    }
                }
            }
        }
    }
}
