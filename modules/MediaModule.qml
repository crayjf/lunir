import QtQuick 2.15
import Quickshell.Services.Mpris
import Quickshell.Widgets
import "../lib"

Item {
    id: root

    property var moduleConfig: null

    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property color _mutedText: Theme.textMuted
    readonly property color _softText: Theme.textMuted

    readonly property var players: Mpris.players.values
    readonly property var player: {
        const active = root.players.find(function(p) { return p.isPlaying })
        return active || (root.players.length > 0 ? root.players[0] : null)
    }

    property string playerName: player ? (player.identity || "").toUpperCase() : ""
    property string title: player ? (player.trackTitle || "NO PLAYER") : "NO PLAYER"
    property string artist: player ? (player.trackArtist || "Waiting for playback") : "Waiting for playback"
    property string artPath: player ? (player.trackArtUrl || "") : ""
    property bool playing: player ? player.isPlaying : false
    property string timeText: player ? root._formatProgress() : ""
    property real progress: player && player.lengthSupported && player.length > 0
        ? Math.min(player.position / player.length, 1.0)
        : 0.0

    function _fmtTime(seconds) {
        const total = Math.max(0, Math.floor(seconds || 0))
        const m = Math.floor(total / 60)
        return m + ":" + String(total % 60).padStart(2, "0")
    }

    function _formatProgress() {
        if (!player || !player.lengthSupported || player.length <= 0) return ""
        return _fmtTime(player.position) + " / " + _fmtTime(player.length)
    }

    function _controlIconOffsetX(label) {
        switch (label) {
            case "⏸": return 1
            default: return 0
        }
    }

    function _controlIconOffsetY(label) {
        switch (label) {
            case "⏮":
            case "⏸":
            case "▶":
            case "⏭":
                return 1
            default:
                return 0
        }
    }

    Timer {
        running: root.playing && !!root.player
        interval: 1000
        repeat: true
        onTriggered: root.timeText = root._formatProgress()
    }

    Item {
        anchors.fill: parent

        Row {
            id: contentRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 5
            height: 102
            spacing: 14

            Item {
                width: 102
                height: parent.height

                Rectangle {
                    id: artGlow
                    width: parent.width
                    height: parent.height
                    radius: 30
                    anchors.centerIn: parent
                    color: Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.16)
                }

                ClippingRectangle {
                    id: artFrame
                    width: 94
                    height: 94
                    anchors.centerIn: parent
                    radius: 26
                    color: Theme.accent

                    Image {
                        anchors.fill: parent
                        source: root.artPath
                        fillMode: Image.PreserveAspectCrop
                        visible: root.artPath !== ""
                    }

                    Rectangle {
                        anchors.fill: parent
                        visible: root.artPath === ""
                        color: Theme.accent
                    }

                    Text {
                        anchors.centerIn: parent
                        visible: root.artPath === ""
                        text: "♫"
                        font.family: Theme.fontFamily
                        font.pixelSize: 30
                        color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.35)
                    }
                }
            }

            Item {
                id: sideContent
                width: parent.width - 102 - parent.spacing
                height: parent.height

                Column {
                    id: textColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: -14
                    spacing: 6

                    Text {
                        width: parent.width
                        text: root.playerName || "MEDIA"
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        font.letterSpacing: 2.2
                        color: root._softText
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.title
                        font.family: Theme.fontFamily
                        font.pixelSize: 18
                        font.bold: true
                        color: root._textColor
                        wrapMode: Text.WordWrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: root.artist
                        font.family: Theme.fontFamily
                        font.pixelSize: 11
                        color: root._mutedText
                        elide: Text.ElideRight
                    }
                }

                Item {
                    id: statusRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 34

                    Rectangle {
                        id: statusPill
                        width: 60
                        height: 20
                        radius: 10
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.18)

                        Text {
                            anchors.centerIn: parent
                            text: root.playing ? "PLAYING" : "PAUSED"
                            font.family: Theme.fontFamily
                            font.pixelSize: 8
                            font.letterSpacing: 1.6
                            color: root.playing ? root._textColor : root._mutedText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Text {
                        id: timeTextItem
                        anchors.left: statusPill.right
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.timeText
                        font.family: Theme.fontFamily
                        font.pixelSize: 9
                        color: root._softText
                        verticalAlignment: Text.AlignVCenter
                        height: parent.height
                    }

                    Item {
                        anchors.left: timeTextItem.right
                        anchors.leftMargin: 6
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        height: 34

                        Row {
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Repeater {
                                model: [
                                    { label: "⏮", enabled: root.player && root.player.canGoPrevious, run: function() { root.player.previous() } },
                                    { label: root.playing ? "⏸" : "▶", enabled: root.player && root.player.canTogglePlaying, run: function() { root.player.togglePlaying() } },
                                    { label: "⏭", enabled: root.player && root.player.canGoNext, run: function() { root.player.next() } }
                                ]

                                delegate: Rectangle {
                                    width: index === 1 ? 34 : 28
                                    height: index === 1 ? 34 : 28
                                    radius: index === 1 ? 17 : 14
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: modelData.enabled ? 1.0 : 0.30
                                    color: hover.containsMouse
                                        ? Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, index === 1 ? 0.55 : 0.35)
                                        : Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, index === 1 ? 0.18 : 0.12)

                                    Text {
                                        anchors.centerIn: parent
                                        anchors.horizontalCenterOffset: root._controlIconOffsetX(modelData.label)
                                        anchors.verticalCenterOffset: root._controlIconOffsetY(modelData.label)
                                        text: modelData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: index === 1 ? 15 : 12
                                        color: root._textColor
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }

                                    MouseArea {
                                        id: hover
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        enabled: modelData.enabled
                                        onClicked: modelData.run()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Item {
            id: progressTrack
            x: 0
            width: parent.width
            y: parent.height - 18
            height: 8

            Rectangle {
                anchors.fill: parent
                radius: 4
                color: Theme.track
            }

            Rectangle {
                width: Math.max(10, parent.width * root.progress)
                height: parent.height
                topLeftRadius: 4
                bottomLeftRadius: 4
                topRightRadius: 2
                bottomRightRadius: 2
                color: root._accentColor
            }

            Rectangle {
                width: 3
                height: 14
                radius: 1.5
                x: Math.max(0, Math.min(parent.width - width, (parent.width * root.progress) - (width / 2) + 4))
                anchors.verticalCenter: parent.verticalCenter
                color: Theme.text
            }
        }
    }
}
