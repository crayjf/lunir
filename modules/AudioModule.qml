import QtQuick 2.15
import Quickshell.Io 0.1
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    property int  volume: 0
    property bool muted:  false
    property bool _dragging: false

    // ── Read volume ───────────────────────────────────────────────────────────
    Process {
        id: volProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: false
        stdout: StdioCollector { id: volStdio }
        onExited: {
            const txt = volStdio.text.trim()
            const m = txt.match(/Volume:\s*([\d.]+)/)
            if (m) root.volume = Math.min(100, Math.round(parseFloat(m[1]) * 100))
            root.muted = txt.includes("[MUTED]")
        }
    }

    // ── Set volume ────────────────────────────────────────────────────────────
    Process {
        id: setProc
        property string pct: "50%"
        command: ["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", setProc.pct]
        running: false
    }

    Process {
        id: muteProc
        command: ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]
        running: false
        onExited: volProc.running = true
    }

    Timer { id: debounce; interval: 40; repeat: false
        onTriggered: { setProc.pct = root.volume + "%"; setProc.running = true }
    }

    Timer {
        interval: 200; repeat: true
        running: root.visible; triggeredOnStart: true
        onTriggered: { if (!root._dragging) volProc.running = true }
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Row {
        anchors { fill: parent; margins: 10 }
        spacing: 10

        // Mute button
        Rectangle {
            width: 32; height: 32
            anchors.verticalCenter: parent.verticalCenter
            color: root.muted
                ? Qt.rgba(Theme.accentColor.r, Theme.accentColor.g, Theme.accentColor.b, 0.18)
                : "transparent"
            radius: 4
            Text {
                anchors.centerIn: parent
                text: root.muted ? "🔇" : root.volume > 50 ? "🔊" : root.volume > 0 ? "🔉" : "🔈"
                font.pixelSize: 16
            }
            MouseArea { anchors.fill: parent; onClicked: muteProc.running = true }
        }

        // Bar
        Item {
            width: parent.width - 32 - volLabel.width - 20
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter

            Rectangle {
                width: parent.width; height: 6
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1, 1, 1, 0.10); radius: 3
                Rectangle {
                    width: parent.width * (root.volume / 100)
                    height: parent.height; radius: parent.radius
                    color: root.muted
                        ? Qt.rgba(Theme.accentColor.r, Theme.accentColor.g, Theme.accentColor.b, 0.4)
                        : Theme.accentColor
                    Behavior on width { NumberAnimation { duration: 80 } }
                }
            }

            MouseArea {
                anchors.fill: parent
                onPressed:          (e) => { root._dragging = true;  _setFromX(e.x) }
                onReleased:               { root._dragging = false }
                onPositionChanged:  (e) => { if (root._dragging) _setFromX(e.x) }

                function _setFromX(x) {
                    root.volume = Math.max(0, Math.min(100, Math.round(x / width * 100)))
                    debounce.restart()
                }
            }
        }

        Text {
            id: volLabel
            text: root.volume + "%"
            width: 36; font.pixelSize: 10; color: Theme.textColor
            horizontalAlignment: Text.AlignRight
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
