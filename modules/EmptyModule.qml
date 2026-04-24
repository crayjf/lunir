import QtQuick 2.15
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")

    Text {
        anchors.centerIn: parent
        text: "Empty Widget"
        font.family: Theme.fontFamily
        font.pixelSize: 12
        font.letterSpacing: 1
        color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.4)
    }
}
