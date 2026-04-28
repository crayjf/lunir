import QtQuick 2.15
import Quickshell
import Quickshell.Io
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")

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
    readonly property string _cachePath: Quickshell.dataPath("quote-cache.json")

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
                    root._saveCache(quotes)
                } else {
                    root._pool = root._FALLBACK
                }
            } catch (_) { root._pool = root._FALLBACK }
            if (root._pool.length > 0 && root.quoteText === "…") {
                root._idx = Math.floor(Math.random() * root._pool.length)
                root._showCurrent()
            }
        }
    }

    Process {
        id: saveCacheProc
        property string content: ""
        command: ["sh", "-c",
            "mkdir -p \"$(dirname \"$1\")\" && printf '%s' \"$2\" > \"$1\"",
            "sh", root._cachePath, saveCacheProc.content]
        running: false
    }

    function _saveCache(quotes) {
        const today = new Date().toISOString().slice(0, 10)
        saveCacheProc.content = JSON.stringify({ date: today, quotes: quotes })
        saveCacheProc.running = true
    }

    function _fetchToday() {
        if (_fetching) return
        _fetching = true
        quoteText = "…"
        fetchProc.endpoint = "today"
        fetchProc.running = true
    }

    function _fetchRandom() {
        if (_fetching) return
        _fetching = true
        fetchProc.endpoint = "random"
        fetchProc.running = true
    }

    function _showCurrent() {
        if (_pool.length === 0) return
        const q = _pool[_idx % _pool.length]
        quoteText  = "\"" + q.text + "\""
        authorText = "— " + q.author
    }

    function _nextQuote() {
        if (_fetching) return
        _idx++
        if (_idx >= _pool.length) {
            const msSince = Date.now() - _lastFetchMs
            if (msSince < 5000) { _idx = 0; _showCurrent(); return }
            _fetchRandom()
        } else {
            _showCurrent()
        }
    }

    // Midnight reset
    Timer {
        id: midnightTimer
        repeat: false
        onTriggered: {
            root._pool = []
            root._idx  = 0
            root._fetchToday()
            const now = new Date()
            const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
            interval = midnight.getTime() - now.getTime()
            restart()
        }
        Component.onCompleted: {
            const now = new Date()
            const midnight = new Date(now.getFullYear(), now.getMonth(), now.getDate() + 1)
            interval = midnight.getTime() - now.getTime()
            start()
        }
    }

    Component.onCompleted: { readCacheProc.running = true }

    readonly property real preferredHeight: quoteColumn.implicitHeight + 20

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        id: quoteColumn
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: 12 }
        anchors.topMargin: 10
        spacing: 10

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

        Text {
            text: root.authorText
            font.family: Theme.fontFamily
            font.pixelSize: 11
            font.letterSpacing: 1
            color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.6)
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root._nextQuote()
    }
}
