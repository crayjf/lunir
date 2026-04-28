import QtQuick 2.15
import QtQuick.Controls 2.15
import Quickshell
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import "../lib"

PanelWindow {
    id: win

    aboveWindows: true
    screen: Quickshell.screens[0]
    focusable: false
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: Config.namespaceFor("volume")
    anchors { bottom: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    visible: false
    implicitWidth: 360
    implicitHeight: 52

    margins { bottom: 34 }

    readonly property var _sink: Pipewire.defaultAudioSink
    readonly property var _sinkAudio: _sink ? _sink.audio : null
    readonly property color _textColor: Theme.text
    readonly property color _accentColor: Theme.accent
    readonly property color _panelColor: Theme.background
    readonly property color _trackColor: Theme.track
    readonly property color _mutedText: Theme.textMuted

    property real fadeOpacity: 0.0
    property int volumeLevel: _sinkAudio ? Math.round((_sinkAudio.volume || 0) * 100) : 0
    property bool volumeMuted: _sinkAudio ? !!_sinkAudio.muted : false

    PwObjectTracker {
        objects: [ win._sink ]
    }

    Behavior on fadeOpacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }

    onFadeOpacityChanged: {
        if (fadeOpacity <= 0.0) visible = false
    }

    Rectangle {
        id: frame
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: Qt.rgba(win._panelColor.r, win._panelColor.g, win._panelColor.b, win._panelColor.a * win.fadeOpacity)
        border.width: Theme.borderWidth
        border.color: Qt.rgba(Theme.border.r, Theme.border.g, Theme.border.b, Theme.border.a * win.fadeOpacity)
        opacity: win.fadeOpacity

        RainbowBorder {
            anchors.fill: parent
            visible: Theme.borderIsRainbow && Theme.borderWidth > 0
            radius: parent.radius
            lineWidth: Theme.borderWidth
        }

        Row {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 14
            anchors.topMargin: 10
            anchors.bottomMargin: 10
            spacing: 12

            Rectangle {
                id: iconButton
                width: 32
                height: 32
                radius: Theme.radiusSmall
                anchors.verticalCenter: parent.verticalCenter
                color: win.volumeMuted
                    ? Qt.rgba(win._accentColor.r, win._accentColor.g, win._accentColor.b, 0.18)
                    : Theme.accent

                Canvas {
                    anchors.centerIn: parent
                    width: 24
                    height: 24

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        const c = win.volumeMuted ? win._mutedText : win._textColor
                        const r = Math.round(c.r * 255)
                        const g = Math.round(c.g * 255)
                        const b = Math.round(c.b * 255)
                        const a = Math.max(0, Math.min(1, c.a))
                        ctx.strokeStyle = "rgba(" + r + "," + g + "," + b + "," + a + ")"
                        ctx.fillStyle = ctx.strokeStyle
                        ctx.lineWidth = 2
                        ctx.lineCap = "round"
                        ctx.lineJoin = "round"

                        ctx.beginPath()
                        ctx.moveTo(4, 10)
                        ctx.lineTo(8, 10)
                        ctx.lineTo(13, 6)
                        ctx.lineTo(13, 18)
                        ctx.lineTo(8, 14)
                        ctx.lineTo(4, 14)
                        ctx.closePath()
                        ctx.fill()

                        if (win.volumeMuted || win.volumeLevel <= 0) {
                            ctx.beginPath()
                            ctx.moveTo(16, 8)
                            ctx.lineTo(21, 16)
                            ctx.moveTo(21, 8)
                            ctx.lineTo(16, 16)
                            ctx.stroke()
                            return
                        }

                        ctx.beginPath()
                        ctx.arc(14, 12, 4, -0.85, 0.85, false)
                        ctx.stroke()

                        if (win.volumeLevel > 45) {
                            ctx.beginPath()
                            ctx.arc(14, 12, 7, -0.85, 0.85, false)
                            ctx.stroke()
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width - iconButton.width - parent.spacing
                height: 16
                radius: 8
                anchors.verticalCenter: parent.verticalCenter
                color: win._trackColor

                Rectangle {
                    width: Math.max(0, Math.min(parent.width, parent.width * (win.volumeLevel / 100)))
                    height: parent.height
                    radius: parent.radius
                    color: win.volumeMuted ? win._mutedText : win._accentColor
                }
            }
        }
    }

    Timer {
        id: dismissTimer
        interval: 1200
        repeat: false
        onTriggered: win.fadeOpacity = 0.0
    }

    function _show() {
        dismissTimer.restart()
        visible = true
        fadeOpacity = 1.0
    }

    function _hide() {
        dismissTimer.stop()
        fadeOpacity = 0.0
    }

    Component.onCompleted: {
        ModuleControllers.register("volume-osd", {
            "show": function() { win._show() },
            "hide": function() { win._hide() },
            "toggle": function() { if (win.fadeOpacity > 0) win._hide(); else win._show() },
            "isVisible": function() { return win.fadeOpacity > 0 }
        })
    }

    Component.onDestruction: {
        ModuleControllers.unregister("volume-osd")
    }
}
