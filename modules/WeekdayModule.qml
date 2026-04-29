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
    readonly property string _font: Theme.value(moduleConfig, "font", "Anurati")
    readonly property var _days: ["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"]

    property string dayText: ""

    function _tick() {
        const now = new Date()
        dayText = _days[now.getDay()]
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
        text: root.dayText
        visible: !root._isRainbow
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: root._font
        font.pixelSize: Math.max(12, Math.round(parent.height * 1.2))
        font.letterSpacing: 4
        color: root._textColor
    }

    Text {
        id: maskText
        anchors.fill: parent
        visible: root._isRainbow
        text: root.dayText
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
        font.family: root._font
        font.pixelSize: Math.max(12, Math.round(parent.height * 1.2))
        font.letterSpacing: 4
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
