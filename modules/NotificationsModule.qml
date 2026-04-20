import QtQuick 2.15
import QtQuick.Controls 2.15
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    property var _notifs: []

    Connections {
        target: NotificationService
        function onNotificationAdded()   { root._notifs = NotificationService.notifications.slice() }
        function onNotificationRemoved() { root._notifs = NotificationService.notifications.slice() }
    }

    Component.onCompleted: {
        _notifs = NotificationService.notifications.slice()
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    ScrollView {
        anchors.fill: parent
        clip: true
        ScrollBar.vertical.policy: ScrollBar.AsNeeded
        ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

        Column {
            width: parent.width
            spacing: 0

            Item {
                width: parent.width; height: 60
                visible: root._notifs.length === 0
                Text {
                    anchors.centerIn: parent
                    text: "NO NOTIFICATIONS"
                    font.pixelSize: 10; font.letterSpacing: 2
                    color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.35)
                }
            }

            Repeater {
                model: root._notifs
                delegate: Column {
                    width: parent.width
                    spacing: 0

                    Rectangle {
                        visible: index > 0
                        width: parent.width; height: 1
                        color: Qt.rgba(1,1,1,0.06)
                    }

                    Rectangle {
                        width: parent.width
                        height: notifCol.implicitHeight + 16
                        color: notifMA.containsMouse ? Qt.rgba(1,1,1,0.05) : "transparent"

                        Column {
                            id: notifCol
                            anchors { fill: parent; margins: 10 }
                            spacing: 3

                            Text {
                                // Live Notification uses .appName (not .app)
                                text: (modelData.appName || "").toUpperCase()
                                font.pixelSize: 9; font.letterSpacing: 1
                                color: Theme.accentColor
                            }
                            Text {
                                text: modelData.summary || ""
                                width: parent.width
                                font.pixelSize: 11; color: Theme.textColor
                                wrapMode: Text.WordWrap
                            }
                            Text {
                                visible: !!(modelData.body)
                                text: modelData.body || ""
                                width: parent.width
                                font.pixelSize: 10
                                color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.65)
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
                                    // Invoke the default action if one exists
                                    const actions = modelData.actions
                                    if (actions && actions.length > 0) actions[0].invoke()
                                } else {
                                    // Right-click: dismiss
                                    modelData.close()
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
