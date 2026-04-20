import QtQuick 2.15
import QtQuick.Controls 2.15
import Quickshell.Io 0.1
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    property var    _packages: []
    property bool   _fetching: false
    property string _status:   "UPDATES"

    // ── Cache ─────────────────────────────────────────────────────────────────
    Process {
        id: readCacheProc
        command: ["sh", "-c", "cat \"$HOME/.local/share/lunir/updates-cache.json\""]
        running: false
        stdout: StdioCollector { id: readCacheStdio }
        onExited: (code) => {
            if (code !== 0) return
            try {
                const data = JSON.parse(readCacheStdio.text)
                if (Array.isArray(data)) root._packages = data
            } catch (_) {}
        }
    }

    Process {
        id: saveCacheProc
        property string content: ""
        command: ["sh", "-c",
            "mkdir -p \"$HOME/.local/share/lunir\" && printf '%s' \"$1\" > \"$HOME/.local/share/lunir/updates-cache.json\"",
            "sh", saveCacheProc.content]
        running: false
    }

    // ── checkupdates ─────────────────────────────────────────────────────────
    Process {
        id: checkProc
        command: ["checkupdates"]
        running: false
        stdout: StdioCollector { id: checkStdio }
        onExited: {
            root._fetching = false
            const lines = checkStdio.text.trim().split("\n").filter(function(l) { return l.trim() })
            root._packages = lines
            root._status = "UPDATES"
            saveCacheProc.content = JSON.stringify(lines)
            saveCacheProc.running = true
        }
    }

    // ── Update terminal ───────────────────────────────────────────────────────
    Process {
        id: updateProc
        command: ["ghostty", "-e", "sh", "-c", "paru -Syu; echo; read -p 'Press enter to close...'"]
        running: false
        onExited: ModuleControllers.hide("overlay")
    }

    function _fetch() {
        if (_fetching) return
        _fetching = true
        _status = "CHECKING…"
        checkProc.running = true
    }

    Component.onCompleted: {
        readCacheProc.running = true
        _fetch()
    }

    onVisibleChanged: { if (visible) _fetch() }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors { fill: parent; margins: 10 }
        spacing: 8

        // Header
        Row {
            width: parent.width
            Text {
                text: root._packages.length > 0
                    ? "UPDATES  ·  " + root._packages.length
                    : root._status
                font.pixelSize: 10; font.letterSpacing: 1
                color: Theme.textColor
                width: parent.width - refreshBtn.width
            }
            Rectangle {
                id: refreshBtn
                width: 22; height: 22; radius: 3
                color: refreshMA.containsMouse ? Qt.rgba(1,1,1,0.12) : "transparent"
                Text { anchors.centerIn: parent; text: "↻"; font.pixelSize: 14; color: Theme.textColor }
                MouseArea { id: refreshMA; anchors.fill: parent; hoverEnabled: true; onClicked: root._fetch() }
            }
        }

        // Package list
        ScrollView {
            width: parent.width
            height: parent.height - 36 - (updateBtn.visible ? 34 : 0)
            clip: true
            ScrollBar.vertical.policy: ScrollBar.AsNeeded
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

            Column {
                width: parent.width
                spacing: 2

                // Empty state
                Item {
                    width: parent.width; height: 50
                    visible: root._packages.length === 0 && !root._fetching
                    Text {
                        anchors.centerIn: parent
                        text: "SYSTEM UP TO DATE"
                        font.pixelSize: 10; font.letterSpacing: 1
                        color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.4)
                    }
                }

                // Checking state
                Item {
                    width: parent.width; height: 50
                    visible: root._fetching && root._packages.length === 0
                    Text {
                        anchors.centerIn: parent
                        text: "checking for updates…"
                        font.pixelSize: 10
                        color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.4)
                    }
                }

                Repeater {
                    model: root._packages
                    delegate: Row {
                        width: parent.width; height: 22
                        spacing: 8
                        Text {
                            width: parent.width - verLabel.width - 8
                            text: {
                                const m = modelData.match(/^(\S+)/)
                                return m ? m[1] : modelData
                            }
                            font.pixelSize: 10; color: Theme.textColor
                            elide: Text.ElideRight
                            verticalAlignment: Text.AlignVCenter; height: parent.height
                        }
                        Text {
                            id: verLabel
                            text: {
                                const m = modelData.match(/\S+\s+\S+\s+->\s+(\S+)/)
                                return m ? m[1] : ""
                            }
                            font.pixelSize: 10
                            color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.5)
                            verticalAlignment: Text.AlignVCenter; height: parent.height
                        }
                    }
                }
            }
        }

        // Update button
        Rectangle {
            id: updateBtn
            visible: root._packages.length > 0
            width: parent.width; height: 28; radius: 3
            color: updateMA.containsMouse ? Qt.rgba(Theme.accentColor.r,Theme.accentColor.g,Theme.accentColor.b,0.35)
                                          : Qt.rgba(Theme.accentColor.r,Theme.accentColor.g,Theme.accentColor.b,0.18)
            Text {
                anchors.centerIn: parent
                text: "UPDATE SYSTEM"
                font.pixelSize: 10; font.letterSpacing: 1; color: Theme.textColor
            }
            MouseArea {
                id: updateMA; anchors.fill: parent; hoverEnabled: true
                onClicked: { ModuleControllers.hide("overlay"); updateProc.running = true }
            }
        }
    }
}
