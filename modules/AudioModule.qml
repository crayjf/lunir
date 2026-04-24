import QtQuick 2.15
import Quickshell.Services.Pipewire
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")

    readonly property var sink: Pipewire.defaultAudioSink
    readonly property var sinkAudio: sink ? sink.audio : null
    property int volume: 0
    property bool muted: false
    property bool _dragging: false

    PwObjectTracker {
        objects: [ root.sink ]
    }

    function _syncFromSink() {
        if (!sinkAudio || _dragging) return
        root.volume = Math.round((sinkAudio.volume || 0) * 100)
        root.muted = !!sinkAudio.muted
    }

    function _applyVolume() {
        if (!sinkAudio) return
        sinkAudio.volume = Math.max(0, Math.min(1, root.volume / 100))
    }

    function _toggleMute() {
        if (!sinkAudio) return
        sinkAudio.muted = !sinkAudio.muted
    }

    onSinkAudioChanged: _syncFromSink()

    Connections {
        target: root.sinkAudio
        function onVolumeChanged() { root._syncFromSink() }
        function onMutedChanged() { root._syncFromSink() }
    }

    Component.onCompleted: _syncFromSink()

    Row {
        anchors { fill: parent; margins: 10 }
        spacing: 10

        Rectangle {
            width: 34
            height: 34
            anchors.verticalCenter: parent.verticalCenter
            color: root.muted
                ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.18)
                : Qt.rgba(1, 1, 1, 0.04)
            radius: 8

            Item {
                anchors.centerIn: parent
                width: 24
                height: 24

                Canvas {
                    anchors.centerIn: parent
                    width: 24
                    height: 24

                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.clearRect(0, 0, width, height)

                        const r = Math.round(root._textColor.r * 255)
                        const g = Math.round(root._textColor.g * 255)
                        const b = Math.round(root._textColor.b * 255)
                        ctx.strokeStyle = "rgb(" + r + "," + g + "," + b + ")"
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

                        if (root.muted || root.volume <= 0) {
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

                        if (root.volume > 45) {
                            ctx.beginPath()
                            ctx.arc(14, 12, 7, -0.85, 0.85, false)
                            ctx.stroke()
                        }
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: root._toggleMute()
            }
        }

        Item {
            width: parent.width - 44
            height: parent.height
            anchors.verticalCenter: parent.verticalCenter

                Rectangle {
                    width: parent.width
                    height: 24
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.rgba(1, 1, 1, 0.10)
                    radius: 8

                    Rectangle {
                        width: parent.width * (root.volume / 100)
                        height: parent.height
                        topLeftRadius: 8
                        bottomLeftRadius: 8
                        topRightRadius: 3
                        bottomRightRadius: 3
                        color: root.muted
                            ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.4)
                            : root._accentColor
                    }

                Rectangle {
                    width: 4
                    height: parent.height + 8
                    radius: 2
                    x: Math.max(0, Math.min(parent.width - width, (parent.width * (root.volume / 100)) - (width / 2) + 6))
                    anchors.verticalCenter: parent.verticalCenter
                    color: Qt.rgba(1, 1, 1, 0.92)
                }
            }

            MouseArea {
                anchors.fill: parent
                onPressed: (e) => {
                    root._dragging = true
                    _setFromX(e.x)
                }
                onReleased: root._dragging = false
                onCanceled: root._dragging = false
                onPositionChanged: (e) => {
                    if (root._dragging) _setFromX(e.x)
                }

                function _setFromX(x) {
                    root.volume = Math.max(0, Math.min(100, Math.round(x / width * 100)))
                    root._applyVolume()
                }
            }
        }
    }
}
