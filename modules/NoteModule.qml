import QtQuick 2.15
import QtQuick.Controls 2.15
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    readonly property var _cfg:  moduleConfig ? (moduleConfig.props || {}) : {}
    property string _title: ""
    property string _body:  ""
    property string _color: ""
    property bool   _loaded: false

    readonly property var _COLORS: ["#a6e3a1", "#89b4fa", "#fab387", "#f38ba8", "#cba6f7"]

    onModuleConfigChanged: {
        if (moduleConfig && !_loaded) {
            _loaded = true
            const p = moduleConfig.props || {}
            titleField.text = p.title || ""
            bodyArea.text   = p.body  || ""
            _color          = p.color || ""
        }
    }

    // ── Debounced save ────────────────────────────────────────────────────────
    Timer {
        id: saveTimer; interval: 800; repeat: false
        onTriggered: root._doSave()
    }
    function _save() { saveTimer.restart() }
    function _doSave() {
        if (!root.moduleConfig) return
        Config.updateModule(root.moduleConfig.id, {
            props: { title: root._title, body: root._body, color: root._color || undefined }
        })
    }

    Component.onDestruction: {
        if (!moduleConfig) return
        const p = moduleConfig.props || {}
        if (_title !== (p.title || "") || _body !== (p.body || ""))
            _doSave()
    }

    // ── Layout ────────────────────────────────────────────────────────────────
    Row {
        anchors.fill: parent
        spacing: 0

        // Accent bar
        Rectangle {
            width: 5; height: parent.height
            radius: 2
            color: root._color || "transparent"
        }

        Column {
            width: parent.width - 5
            height: parent.height
            spacing: 0

            // Header row
            Row {
                width: parent.width; height: 32
                spacing: 6
                leftPadding: 8; rightPadding: 8

                Rectangle {
                    id: closeBtn
                    width: 18; height: 18
                    anchors.verticalCenter: parent.verticalCenter
                    color: closeHover.containsMouse ? Qt.rgba(1,1,1,0.15) : "transparent"
                    radius: 3
                    Text {
                        anchors.centerIn: parent; text: "✕"
                        font.pixelSize: 9; color: Theme.textColor
                    }
                    MouseArea {
                        id: closeHover; anchors.fill: parent; hoverEnabled: true
                        onClicked: { if (root.moduleConfig) Config.removeModule(root.moduleConfig.id) }
                    }
                }

                TextField {
                    id: titleField
                    width: parent.width - 18 - (root._COLORS.length * 15) - parent.spacing * 2 - parent.leftPadding - parent.rightPadding
                    height: parent.height
                    text: root._title
                    placeholderText: "Title"
                    background: null
                    font.pixelSize: 11
                    color: Theme.textColor
                    onTextChanged: { root._title = text; root._save() }
                    Keys.onReturnPressed: bodyArea.forceActiveFocus()
                }

                // Color swatches
                Row {
                    spacing: 4
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: root._COLORS
                        delegate: Rectangle {
                            width: 10; height: 10; radius: 5
                            color: modelData
                            border.width: root._color === modelData ? 2 : 0
                            border.color: Qt.rgba(1,1,1,0.8)
                            anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                            MouseArea {
                                anchors.fill: parent
                                onClicked: { root._color = (root._color === modelData) ? "" : modelData; root._save() }
                            }
                        }
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.10) }

            // Body
            ScrollView {
                width: parent.width
                height: parent.height - 33
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded
                ScrollBar.horizontal.policy: ScrollBar.AlwaysOff

                TextArea {
                    id: bodyArea
                    width: parent.width
                    text: root._body
                    placeholderText: "Note…"
                    background: null
                    wrapMode: TextEdit.WordWrap
                    font.pixelSize: 11
                    color: Theme.textColor
                    topPadding: 8; leftPadding: 8; rightPadding: 8; bottomPadding: 8
                    onTextChanged: { root._body = text; root._save() }
                }
            }
        }
    }
}
