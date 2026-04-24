import QtQuick 2.15
import QtQuick.Controls 2.15
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property color _mutedText: Theme.textMuted
    readonly property color _softText: Theme.textMuted
    readonly property var _cfg: moduleConfig ? (moduleConfig.props || {}) : ({})
    readonly property bool _nativePanel: _cfg.nativePanel === true
    readonly property int _maxVisibleNotifications: 3

    property var _notifs: []
    readonly property var _visibleNotifs: _notifs.slice(0, _maxVisibleNotifications)
    readonly property int _hiddenCount: Math.max(0, _notifs.length - _maxVisibleNotifications)

    Connections {
        target: NotificationService
        function onNotificationAdded()   { root._notifs = NotificationService.notifications.slice() }
        function onNotificationRemoved() { root._notifs = NotificationService.notifications.slice() }
    }

    Component.onCompleted: {
        _notifs = NotificationService.notifications.slice()
    }

    Item {
        anchors.fill: parent
        clip: true

        Column {
            width: parent.width
            spacing: root._nativePanel ? 8 : 10

            Item {
                width: parent.width
                height: 24

                Text {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "NOTIFICATIONS"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 1.8
                    color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.6)
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: clearLabel.implicitWidth + 18
                    height: 24
                    radius: 12
                    opacity: root._notifs.length > 0 ? 1.0 : 0.45
                    color: clearMouse.containsMouse && root._notifs.length > 0
                        ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.18)
                        : Theme.surfaceRaised

                    Text {
                        id: clearLabel
                        anchors.centerIn: parent
                        text: "CLEAR ALL"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 1.2
                        color: root._textColor
                    }

                    MouseArea {
                        id: clearMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        enabled: root._notifs.length > 0
                        onClicked: NotificationService.clear()
                    }
                }
            }

            Item {
                width: parent.width
                height: root._nativePanel ? 52 : 64
                visible: root._notifs.length === 0

                Row {
                    anchors.centerIn: parent
                    Rectangle {
                        width: 46
                        height: 28
                        radius: 14
                        color: Theme.surfaceRaised
                        border.width: 1
                        border.color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.08)

                        Rectangle {
                            width: 28
                            height: 6
                            radius: 3
                            anchors.top: parent.top
                            anchors.topMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.12)
                        }

                        Rectangle {
                            width: 20
                            height: 6
                            radius: 3
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: 6
                            anchors.horizontalCenter: parent.horizontalCenter
                            color: Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.18)
                        }
                    }
                }
            }

            Repeater {
                model: root._visibleNotifs
                delegate: Rectangle {
                    width: parent.width
                    height: notifCol.implicitHeight + (root._nativePanel ? 12 : 16)
                    radius: 14
                    color: notifMA.containsMouse ? Theme.surfaceRaised : "transparent"

                    Column {
                        id: notifCol
                        anchors { fill: parent; margins: root._nativePanel ? 8 : 10 }
                        spacing: root._nativePanel ? 2 : 3

                        Text {
                            text: (modelData.appName || "").toUpperCase()
                            font.family: Theme.fontFamily
                            font.pixelSize: 9; font.letterSpacing: 1
                            color: root._accentColor
                        }
                        Text {
                            text: modelData.summary || ""
                            width: parent.width
                            font.family: Theme.fontFamily
                            font.pixelSize: 11; color: root._textColor
                            wrapMode: Text.WordWrap
                        }
                        Text {
                            visible: !!(modelData.body)
                            text: modelData.body || ""
                            width: parent.width
                            font.family: Theme.fontFamily
                            font.pixelSize: 10
                            color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.65)
                            wrapMode: Text.WordWrap
                        }
                    }

                    MouseArea {
                        id: notifMA
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.LeftButton) {
                                if (!NotificationService.invokePrimaryAction(modelData))
                                    NotificationService.dismiss(modelData.id)
                            } else {
                                if (modelData && modelData.id !== undefined)
                                    NotificationService.dismiss(modelData.id)
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 26
                radius: 13
                visible: root._hiddenCount > 0
                color: Theme.surfaceRaised

                Text {
                    anchors.centerIn: parent
                    text: "+" + root._hiddenCount + " MORE"
                    font.family: Theme.fontFamily
                    font.pixelSize: 9
                    font.letterSpacing: 1.4
                    color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.55)
                }
            }
        }
    }
}
