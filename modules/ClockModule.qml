import QtQuick 2.15
import "../lib"

Item {
    id: root
    property var moduleConfig: null

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
        timeText = "- " + h + ":" + m + " -"
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
        anchors { fill: parent; margins: 16 }
        spacing: 6

        // Text block
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 6

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.dayText
                font.family: "Anurati"
                font.pixelSize: 13
                font.letterSpacing: 4
                color: Theme.textColor
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.dateText
                font.pixelSize: 11
                font.letterSpacing: 2
                color: Qt.rgba(Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 0.7)
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: root.timeText
                font.family: "Anurati"
                font.pixelSize: 48
                color: Theme.textColor
            }
        }

        // Day progress bar
        Rectangle {
            width: parent.width
            height: 6
            radius: 3
            color: Qt.rgba(1,1,1,0.1)

            Rectangle {
                width: parent.width * root.dayFrac
                height: parent.height
                radius: parent.radius
                color: Theme.accentColor
            }
        }
    }
}
