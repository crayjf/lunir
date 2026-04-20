import QtQuick 2.15
import QtQuick.Controls 2.15
import Quickshell 0.1
import Quickshell.Wayland 0.1
import Quickshell.Io 0.1
import "../lib"

// Transient volume indicator — shown briefly on volume key presses.
// Registered with ModuleControllers as "volume-osd".
PanelWindow {
    id: win

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "lunir-qs"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; left: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    implicitWidth:  _osdW
    implicitHeight: _osdH

    visible: false

    readonly property var _audioCfg: Config.modules.find(function(m) { return m.type === "audio" }) || null
    readonly property int _osdW: _audioCfg ? (_audioCfg.width  ?? 440) : 440
    readonly property int _osdH: _audioCfg ? (_audioCfg.height ?? 44)  : 44

    margins {
        top:  _audioCfg ? (_audioCfg.y ?? 0) : 0
        left: _audioCfg ? (_audioCfg.x ?? 0) : 0
    }

    property real fadeOpacity: 0.0
    Behavior on fadeOpacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
    onFadeOpacityChanged: { if (fadeOpacity <= 0.0) visible = false }

    // ── Content ───────────────────────────────────────────────────────────────
    Rectangle {
        id: frame
        width: win._osdW; height: win._osdH
        color: Qt.rgba(Theme.widgetBackground.r, Theme.widgetBackground.g, Theme.widgetBackground.b,
                       Theme.widgetBackground.a * Theme.widgetOpacity * win.fadeOpacity)
        radius: Theme.widgetBorderRadius
        border.color: Theme.widgetBorderColor
        border.width: Theme.widgetBorderWidth

        Row {
            anchors { fill: parent; margins: 8 }
            spacing: 10

            Text {
                id: muteIcon
                text: "🔊"
                font.pixelSize: 16
                color: Theme.textColor
                verticalAlignment: Text.AlignVCenter
                height: parent.height
            }

            Rectangle {
                id: barBg
                height: 6
                width: parent.width - muteIcon.width - volLabel.width - 28
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.rgba(1,1,1,0.12)
                radius: 3

                Rectangle {
                    id: barFill
                    height: parent.height
                    width: parent.width * (volumeLevel / 100)
                    color: Theme.accentColor
                    radius: parent.radius
                }
            }

            Text {
                id: volLabel
                text: volumeLevel + "%"
                font.pixelSize: 11
                font.letterSpacing: 0.5
                color: Theme.textColor
                verticalAlignment: Text.AlignVCenter
                height: parent.height
                width: 36
                horizontalAlignment: Text.AlignRight
            }
        }
    }

    // ── Volume state ──────────────────────────────────────────────────────────
    property int  volumeLevel: 0
    property bool volumeMuted: false

    Process {
        id: readProc
        command: ["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]
        running: false

        stdout: StdioCollector {
            id: readStdio
        }

        onExited: {
            const out = readStdio.text.trim()
            const m = out.match(/Volume:\s*([\d.]+)/)
            win.volumeLevel = m ? Math.min(100, Math.round(parseFloat(m[1]) * 100)) : 0
            win.volumeMuted = out.includes("[MUTED]")
            muteIcon.text = win.volumeMuted ? "🔇"
                : win.volumeLevel > 66 ? "🔊"
                : win.volumeLevel > 33 ? "🔉"
                : "🔈"
        }
    }

    // ── Dismiss timer ─────────────────────────────────────────────────────────
    Timer {
        id: dismissTimer
        interval: 1200
        repeat: false
        onTriggered: win.fadeOpacity = 0.0
    }

    // ── Show / hide ───────────────────────────────────────────────────────────
    function _show() {
        if (ModuleControllers.isVisible("overlay")) return
        dismissTimer.restart()
        readProc.running = true
        visible     = true
        fadeOpacity = 1.0
    }

    function _hide() {
        dismissTimer.stop()
        fadeOpacity = 0.0
    }

    Component.onCompleted: {
        ModuleControllers.register("volume-osd", {
            "show":      function() { win._show() },
            "hide":      function() { win._hide() },
            "toggle":    function() { if (win.fadeOpacity > 0) win._hide(); else win._show() },
            "isVisible": function() { return win.fadeOpacity > 0 }
        })
    }

    Component.onDestruction: { ModuleControllers.unregister("volume-osd") }
}
