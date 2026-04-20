import QtQuick 2.15
import Quickshell.Io 0.1
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    property var _allApps: []
    property var _results: []
    property int _selIdx:  0

    // ── Scan .desktop files ───────────────────────────────────────────────────
    Process {
        id: scanProc
        command: ["bash", "-c", "bash \"${1/#~/$HOME}\"", "--",
                  "~/Software/lunir-qs/scripts/scan_apps.sh"]
        running: false
        stdout: StdioCollector { id: scanStdio }
        onExited: {
            const lines = scanStdio.text.trim().split("\n")
            const apps = []
            for (const l of lines) {
                const parts = l.split("|")
                if (parts.length < 2) continue
                apps.push({
                    name: parts[0].trim(),
                    exec: parts[1].trim(),
                    icon: parts.length > 2 ? parts[2].trim() : ""
                })
            }
            root._allApps = apps
            root._filter(searchField.text)
        }
    }

    // ── Launch ────────────────────────────────────────────────────────────────
    Process {
        id: launchProc
        property string cmd: ""
        command: ["bash", "-c", launchProc.cmd + " &"]
        running: false
        onExited: ModuleControllers.hide("overlay")
    }

    // ── Filtering ─────────────────────────────────────────────────────────────
    function _score(name, query) {
        const q = query.toLowerCase()
        const n = name.toLowerCase()
        if (n === q)          return 100
        if (n.startsWith(q))  return 80
        if (n.includes(q))    return 60
        let i = 0
        for (const ch of n) { if (ch === q[i]) i++; if (i === q.length) return 20 }
        return -1
    }

    function _filter(query) {
        const q = query.trim()
        let scored = root._allApps.map(function(a) {
            return { app: a, score: q ? root._score(a.name, q) : 50 }
        }).filter(function(x) { return x.score >= 0 })
        scored.sort(function(a, b) { return b.score - a.score })
        root._results = scored.slice(0, 8).map(function(x) { return x.app })
        root._selIdx  = 0
    }

    function _launch() {
        const idx = Math.min(root._selIdx, root._results.length - 1)
        if (idx < 0) return
        const app = root._results[idx]
        if (!app || !app.exec) return
        launchProc.cmd = app.exec
        launchProc.running = true
    }

    Timer {
        id: focusTimer
        interval: 0
        repeat: false
        onTriggered: searchField.forceActiveFocus()
    }

    onVisibleChanged: {
        if (visible) {
            searchField.text = ""
            root._filter("")
            focusTimer.start()
            if (root._allApps.length === 0) scanProc.running = true
        }
    }
    Component.onCompleted: scanProc.running = true

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors.fill: parent
        spacing: 0

        // Search box
        Rectangle {
            width: parent.width; height: 44
            color: Qt.rgba(1,1,1,0.05)
            Row {
                anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                spacing: 10

                Text {
                    text: "⌕"
                    font.pixelSize: 18
                    color: Qt.rgba(Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 0.4)
                    anchors.verticalCenter: parent.verticalCenter
                }

                TextInput {
                    id: searchField
                    width: parent.width - 28 - parent.spacing
                    height: parent.height
                    verticalAlignment: TextInput.AlignVCenter
                    font.pixelSize: 13; color: Theme.textColor
                    onTextChanged: root._filter(text)
                    Keys.onReturnPressed:  root._launch()
                    Keys.onDownPressed:    root._selIdx = Math.min(root._selIdx + 1, root._results.length - 1)
                    Keys.onUpPressed:      root._selIdx = Math.max(root._selIdx - 1, 0)
                    Keys.onEscapePressed:  ModuleControllers.hide("overlay")

                    Text {
                        visible: !parent.text
                        text: "Search applications…"
                        font: parent.font
                        color: Qt.rgba(Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 0.3)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }

        // Result rows
        Repeater {
            model: root._results
            delegate: Rectangle {
                width: parent.width; height: 44
                color: index === root._selIdx
                    ? Qt.rgba(Theme.accentColor.r, Theme.accentColor.g, Theme.accentColor.b, 0.18)
                    : rowMA.containsMouse ? Qt.rgba(1,1,1,0.05) : "transparent"

                Row {
                    anchors { fill: parent; leftMargin: 12; rightMargin: 12 }
                    spacing: 12

                    // Icon
                    Rectangle {
                        width: 28; height: 28
                        anchors.verticalCenter: parent.verticalCenter
                        color: "transparent"

                        Image {
                            id: appIcon
                            anchors.fill: parent
                            source: modelData.icon ? "file://" + modelData.icon : ""
                            fillMode: Image.PreserveAspectFit
                            visible: status === Image.Ready
                            smooth: true
                            mipmap: true
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: appIcon.status !== Image.Ready
                            text: modelData.name.charAt(0).toUpperCase()
                            font.pixelSize: 13; font.bold: true
                            color: Qt.rgba(Theme.accentColor.r, Theme.accentColor.g, Theme.accentColor.b, 0.7)
                        }
                    }

                    Text {
                        width: parent.width - 28 - parent.spacing
                        text: modelData.name
                        font.pixelSize: 12; color: Theme.textColor
                        verticalAlignment: Text.AlignVCenter
                        height: parent.height
                        elide: Text.ElideRight
                    }
                }

                MouseArea {
                    id: rowMA
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: { root._selIdx = index; root._launch() }
                }
            }
        }
    }
}
