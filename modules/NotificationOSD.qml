import QtQuick 2.15
import Quickshell
import Quickshell.Wayland
import "../lib"

PanelWindow {
    id: win

    aboveWindows: true
    screen: Quickshell.screens[0]
    focusable: false
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: Config.namespaceFor("notification")
    anchors { top: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    visible: false

    readonly property int _w: 420
    readonly property int _gap: 10
    readonly property int _maxItems: 5
    readonly property color _textColor: Theme.text
    readonly property color _panelColor: Theme.background
    readonly property color _mutedText: Theme.textMuted
    readonly property color _softText: Theme.textMuted

    property int _nextToken: 1

    signal closeToken(int token)

    margins { top: 20 }

    implicitWidth: _w
    implicitHeight: stack.implicitHeight

    ListModel {
        id: osdModel
        dynamicRoles: true
    }

    function _removeToken(token) {
        for (let i = 0; i < osdModel.count; i++) {
            if (osdModel.get(i).token === token) {
                osdModel.remove(i)
                break
            }
        }
        if (osdModel.count === 0)
            win.visible = false
    }

    function _removeNotificationId(id) {
        for (let i = osdModel.count - 1; i >= 0; i--) {
            if (osdModel.get(i).id === id)
                osdModel.remove(i)
        }
        if (osdModel.count === 0)
            win.visible = false
    }

    function _closeToken(token) {
        closeToken(token)
    }

    function showNotification(n) {
        osdModel.insert(0, {
            token: _nextToken++,
            id: n.id,
            notification: n,
            app: (n.appName || n.app || "").toUpperCase(),
            summary: n.summary || "",
            body: n.body || ""
        })
        while (osdModel.count > _maxItems)
            osdModel.remove(osdModel.count - 1)
        visible = true
    }

    Column {
        id: stack
        width: win._w
        spacing: win._gap

        Repeater {
            model: osdModel

            Item {
                id: slot
                required property int token
                required property int id
                required property var notification
                required property string app
                required property string summary
                required property string body
                property bool closing: false

                width: win._w
                height: frame.height

                Behavior on y { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

                Connections {
                    target: win
                    function onCloseToken(closeToken) {
                        if (closeToken === slot.token)
                            slot.closing = true
                    }
                }

                Rectangle {
                    id: frame
                    width: win._w
                    height: Math.max(76, contentCol.implicitHeight + 28)
                    radius: Theme.radiusLarge
                    color: win._panelColor
                    border.width: Theme.borderWidth
                    border.color: Theme.border
                    opacity: slot.closing ? 0.0 : 1.0

                    Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                    onOpacityChanged: {
                        if (slot.closing && opacity <= 0.0)
                            win._removeToken(slot.token)
                    }

                    RainbowBorder {
                        anchors.fill: parent
                        visible: Theme.borderIsRainbow && Theme.borderWidth > 0
                        radius: parent.radius
                        lineWidth: Theme.borderWidth
                    }

                    Row {
                        anchors.fill: parent
                        anchors.margins: 14
                        spacing: 12

                        Rectangle {
                            width: 40
                            height: 40
                            radius: Theme.radiusSmall
                            anchors.top: parent.top
                            color: Theme.accent

                            Text {
                                anchors.centerIn: parent
                                text: slot.app.length > 0 ? slot.app.charAt(0) : "!"
                                font.family: Theme.fontFamily
                                font.pixelSize: 15
                                font.bold: true
                                color: win._textColor
                            }
                        }

                        Column {
                            id: contentCol
                            width: parent.width - 52
                            spacing: 5

                            Text {
                                width: parent.width
                                text: slot.app
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.letterSpacing: 1.6
                                color: win._mutedText
                                elide: Text.ElideRight
                                visible: text.length > 0
                            }

                            Text {
                                width: parent.width
                                text: slot.summary
                                font.family: Theme.fontFamily
                                font.pixelSize: 14
                                font.bold: true
                                color: win._textColor
                                wrapMode: Text.WordWrap
                                visible: text.length > 0
                            }

                            Text {
                                width: parent.width
                                text: slot.body
                                font.family: Theme.fontFamily
                                font.pixelSize: 11
                                lineHeight: 1.12
                                color: win._softText
                                wrapMode: Text.WordWrap
                                visible: text.length > 0
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        hoverEnabled: true

                        onClicked: (mouse) => {
                            const notif = slot.notification
                            if (!notif) {
                                win._closeToken(slot.token)
                                return
                            }

                            dismissTimer.stop()

                            if (mouse.button === Qt.RightButton) {
                                notif.dismiss()
                                win._closeToken(slot.token)
                                return
                            }

                            if (!NotificationService.invokePrimaryAction(notif))
                                notif.dismiss()

                            win._closeToken(slot.token)
                        }
                    }
                }

                Timer {
                    id: dismissTimer
                    interval: 5000
                    repeat: false
                    running: !slot.closing
                    onTriggered: win._closeToken(slot.token)
                }
            }
        }
    }

    Connections {
        target: NotificationService
        function onNotificationAdded(n) { win.showNotification(n) }
        function onNotificationRemoved(id) { win._removeNotificationId(id) }
    }
}
