import QtQuick 2.15
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    Text {
        anchors.centerIn: parent
        text: "Empty Widget"
        font.pixelSize: 12
        font.letterSpacing: 1
        color: Qt.rgba(Theme.textColor.r, Theme.textColor.g, Theme.textColor.b, 0.4)
    }
}
