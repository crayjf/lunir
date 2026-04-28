import QtQuick 2.15
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property var _cfg: moduleConfig ? (moduleConfig.props || {}) : ({})
    readonly property bool _nativePanel: _cfg.nativePanel === true

    property var _notifs: []
    property int _viewIndex: 0

    readonly property bool hasNotifications: _notifs.length > 0
    readonly property var _current: _notifs.length > 0 ? _notifs[_viewIndex] : null

    Connections {
        target: NotificationService
        function onNotificationAdded() {
            root._notifs = NotificationService.notifications.slice()
            root._viewIndex = 0
        }
        function onNotificationRemoved() {
            root._notifs = NotificationService.notifications.slice()
            if (root._viewIndex >= root._notifs.length)
                root._viewIndex = Math.max(0, root._notifs.length - 1)
        }
    }

    Component.onCompleted: {
        _notifs = NotificationService.notifications.slice()
    }

    Text {
        anchors.verticalCenter: parent.verticalCenter
        anchors.horizontalCenter: parent.horizontalCenter
        visible: root._notifs.length === 0
        text: "NO NOTIFICATIONS"
        font.family: Theme.fontFamily
        font.pixelSize: 9
        font.letterSpacing: 1.4
        color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.3)
    }

    Item {
        anchors.fill: parent
        visible: root._current !== null

        Text {
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: root._nativePanel ? 8 : 10
            visible: root._notifs.length > 1
            text: (root._viewIndex + 1) + " / " + root._notifs.length
            font.family: Theme.fontFamily
            font.pixelSize: 9
            color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.45)
        }

        Column {
            anchors { fill: parent; margins: root._nativePanel ? 8 : 10 }
            spacing: root._nativePanel ? 2 : 3

            Text {
                text: (root._current ? root._current.appName || "" : "").toUpperCase()
                font.family: Theme.fontFamily
                font.pixelSize: 9; font.letterSpacing: 1
                color: root._accentColor
            }
            Text {
                text: root._current ? root._current.summary || "" : ""
                width: parent.width
                font.family: Theme.fontFamily
                font.pixelSize: 11; color: root._textColor
                wrapMode: cardMA.containsMouse ? Text.WordWrap : Text.NoWrap
                maximumLineCount: cardMA.containsMouse ? 0 : 1
                elide: cardMA.containsMouse ? Text.ElideNone : Text.ElideRight
            }
            Text {
                visible: !!(root._current && root._current.body)
                text: root._current ? root._current.body || "" : ""
                width: parent.width
                font.family: Theme.fontFamily
                font.pixelSize: 10
                color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.65)
                wrapMode: cardMA.containsMouse ? Text.WordWrap : Text.NoWrap
                maximumLineCount: cardMA.containsMouse ? 0 : 1
                elide: cardMA.containsMouse ? Text.ElideNone : Text.ElideRight
            }
        }

        MouseArea {
            id: cardMA
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onWheel: (wheel) => {
                if (wheel.angleDelta.y < 0) {
                    if (root._viewIndex < root._notifs.length - 1)
                        root._viewIndex++
                } else {
                    if (root._viewIndex > 0)
                        root._viewIndex--
                }
            }
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    if (root._current && root._current.id !== undefined)
                        NotificationService.dismiss(root._current.id)
                } else {
                    if (!NotificationService.invokePrimaryAction(root._current))
                        NotificationService.dismiss(root._current.id)
                }
            }
        }
    }
}
