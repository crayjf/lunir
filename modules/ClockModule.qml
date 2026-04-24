import QtQuick 2.15
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")

    readonly property var _DAYS:   ["SUNDAY","MONDAY","TUESDAY","WEDNESDAY","THURSDAY","FRIDAY","SATURDAY"]
    readonly property var _MONTHS: ["JANUARY","FEBRUARY","MARCH","APRIL","MAY","JUNE",
                                    "JULY","AUGUST","SEPTEMBER","OCTOBER","NOVEMBER","DECEMBER"]

    property string dayText:  ""
    property string dateText: ""
    property string timeText: ""
    property real   dayFrac:  0.0

    function _tick() {
        const now = new Date()
        const h = String(now.getHours()).padStart(2, "0")
        const m = String(now.getMinutes()).padStart(2, "0")
        dayText  = _DAYS[now.getDay()]
        dateText = now.getDate() + " " + _MONTHS[now.getMonth()] + " " + now.getFullYear()
        timeText = "-   " + h + ":" + m + "   -"
        dayFrac  = (now.getHours() * 3600 + now.getMinutes() * 60 + now.getSeconds()) / 86400
    }

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._tick()
    }

    Column {
        anchors { left: parent.left; right: parent.right; margins: 16 }
        anchors.verticalCenter: parent.verticalCenter
        spacing: 6

        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dayText
            font.family: "Anurati"
            font.pixelSize: 68
            font.letterSpacing: 4
            color: root._textColor
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.dateText
            font.pixelSize: 15
            font.letterSpacing: 2
            color: root._textColor
            opacity: 0.7
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.timeText
            font.family: "Anurati"
            font.pixelSize: 19
            color: root._textColor
        }
    }

    // Day progress bar
    Rectangle {
        anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 16 }
        height: 6
        radius: 3
        // The trough should be a fixed subtle color so it doesn't vanish if the widget is transparent
        color: Qt.rgba(1, 1, 1, 0.1)
        border.width: 0

        Rectangle {
            width: parent.width * root.dayFrac
            height: parent.height
            radius: parent.radius
            color: root._accentColor
        }
    }
}
