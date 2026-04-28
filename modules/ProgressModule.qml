import QtQuick 2.15
import "../lib"

Item {
    id: root

    property var moduleConfig: null
    readonly property string _colorStr: Theme.value(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property bool _isRainbow: Theme.isRainbow(moduleConfig, "accentColor")
    readonly property real _rainbowAlpha: Theme.rainbowAlpha(moduleConfig, "accentColor")
    readonly property color _accentColor: Theme.parse(_colorStr, "#FF79C6FF")

    property real dayFrac: 0.0

    function _tick() {
        const now = new Date()
        dayFrac = (now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()) / 86400
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._tick()
    }

    Rectangle {
        anchors.fill: parent
        height: parent.height
        radius: Math.round(height / 2)
        color: Qt.rgba(1, 1, 1, 0.1)

        Rectangle {
            id: fillClip
            width: parent.width * root.dayFrac
            height: parent.height
            radius: parent.radius
            color: "transparent"
            clip: true

            Rectangle {
                anchors.fill: parent
                visible: !root._isRainbow
                radius: fillClip.radius
                color: root._accentColor
            }

            Canvas {
                anchors.fill: parent
                visible: root._isRainbow
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.clearRect(0, 0, width, height)

                    const gradient = ctx.createLinearGradient(0, 0, width, 0)
                    gradient.addColorStop(0.00, "rgba(90,255,90," + root._rainbowAlpha.toFixed(3) + ")")
                    gradient.addColorStop(0.18, "rgba(0,255,140," + root._rainbowAlpha.toFixed(3) + ")")
                    gradient.addColorStop(0.36, "rgba(0,220,255," + root._rainbowAlpha.toFixed(3) + ")")
                    gradient.addColorStop(0.56, "rgba(70,120,255," + root._rainbowAlpha.toFixed(3) + ")")
                    gradient.addColorStop(0.76, "rgba(185,90,255," + root._rainbowAlpha.toFixed(3) + ")")
                    gradient.addColorStop(1.00, "rgba(255,80,120," + root._rainbowAlpha.toFixed(3) + ")")

                    ctx.fillStyle = gradient
                    ctx.beginPath()
                    const r = Math.min(height / 2, width / 2)
                    ctx.moveTo(r, 0)
                    ctx.lineTo(width - r, 0)
                    ctx.quadraticCurveTo(width, 0, width, r)
                    ctx.lineTo(width, height - r)
                    ctx.quadraticCurveTo(width, height, width - r, height)
                    ctx.lineTo(r, height)
                    ctx.quadraticCurveTo(0, height, 0, height - r)
                    ctx.lineTo(0, r)
                    ctx.quadraticCurveTo(0, 0, r, 0)
                    ctx.closePath()
                    ctx.fill()
                }
            }
        }
    }
}
