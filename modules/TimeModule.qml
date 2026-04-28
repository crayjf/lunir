import QtQuick 2.15
import Qt5Compat.GraphicalEffects
import "../lib"

Item {
    id: root

    property var moduleConfig: null
    readonly property string _colorStr: Theme.value(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property bool _isRainbow: Theme.isRainbow(moduleConfig, "textColor")
    readonly property real _rainbowAlpha: Theme.rainbowAlpha(moduleConfig, "textColor")
    readonly property color _textColor: _isRainbow
        ? Theme.positionalRainbowColor(moduleConfig, _rainbowAlpha)
        : Theme.parse(_colorStr, "#F8F8F2FF")

    property string timeText: ""

    function _tick() {
        const now = new Date()
        const h = String(now.getHours()).padStart(2, "0")
        const m = String(now.getMinutes()).padStart(2, "0")
        timeText = h + ":" + m
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._tick()
    }

    Text {
        id: plainText
        anchors.fill: parent
        text: root.timeText
        visible: !root._isRainbow
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        fontSizeMode: Text.Fit
        minimumPixelSize: 10
        font.family: "Anurati"
        font.pixelSize: Math.max(10, Math.round(parent.height * 0.68))
        color: root._textColor
    }

    Text {
        id: maskText
        anchors.fill: parent
        visible: root._isRainbow
        text: root.timeText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        fontSizeMode: Text.Fit
        minimumPixelSize: 10
        font.family: "Anurati"
        font.pixelSize: Math.max(10, Math.round(parent.height * 0.68))
        color: "white"
    }

    ShaderEffectSource {
        id: maskSourceProxy
        visible: false
        live: true
        hideSource: true
        sourceItem: maskText
    }

    OpacityMask {
        anchors.fill: parent
        visible: root._isRainbow
        source: Canvas {
            width: root.width
            height: root.height
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const gradient = ctx.createLinearGradient(0, height, width, 0)
                gradient.addColorStop(0.00, "rgba(90,255,90," + root._rainbowAlpha.toFixed(3) + ")")
                gradient.addColorStop(0.16, "rgba(0,255,220," + root._rainbowAlpha.toFixed(3) + ")")
                gradient.addColorStop(0.32, "rgba(0,120,255," + root._rainbowAlpha.toFixed(3) + ")")
                gradient.addColorStop(0.48, "rgba(150,90,255," + root._rainbowAlpha.toFixed(3) + ")")
                gradient.addColorStop(0.64, "rgba(255,80,160," + root._rainbowAlpha.toFixed(3) + ")")
                gradient.addColorStop(0.80, "rgba(255,120,0," + root._rainbowAlpha.toFixed(3) + ")")
                gradient.addColorStop(1.00, "rgba(255,240,60," + root._rainbowAlpha.toFixed(3) + ")")
                ctx.fillStyle = gradient
                ctx.fillRect(0, 0, width, height)
            }
        }
        maskSource: maskSourceProxy
    }
}
