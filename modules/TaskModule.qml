import QtQuick 2.15
import QtQuick.Controls 2.15
import "../lib"

Item {
    id: taskRoot

    property var moduleConfig: null

    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _mutedText: Theme.textMuted
    readonly property color _accentColor: Theme.accent

    ListModel {
        id: taskModel
    }

    property bool _syncingFromConfig: false

    function _loadFromConfig() {
        if (!Config.loaded)
            return

        _syncingFromConfig = true
        taskModel.clear()

        const tasks = Array.isArray(Config.task) ? Config.task : []
        for (const task of tasks) {
            if (typeof task === "string")
                taskModel.append({ text: task })
        }

        if (taskModel.count === 0 || taskModel.get(taskModel.count - 1).text !== "")
            taskModel.append({ text: "" })

        _syncingFromConfig = false
    }

    function _persistTasks(saveNow) {
        if (_syncingFromConfig)
            return

        const tasks = []
        for (let i = 0; i < taskModel.count; i++) {
            const value = String(taskModel.get(i).text || "").trim()
            if (value !== "")
                tasks.push(value)
        }

        Config.updateTask(tasks)
        if (saveNow)
            Config.saveImmediate()
    }

    function _queueSave() {
        saveTimer.restart()
    }

    function _removeTaskAt(index) {
        if (index < 0 || index >= taskModel.count)
            return
        taskModel.remove(index)
        _ensureTrailingEmpty()
        _persistTasks(true)
    }

    function _ensureTrailingEmpty() {
        if (taskModel.count === 0 || taskModel.get(taskModel.count - 1).text !== "")
            taskModel.append({ text: "" })
    }

    Timer {
        id: saveTimer
        interval: 350
        repeat: false
        onTriggered: taskRoot._persistTasks(false)
    }

    Connections {
        target: Config
        function onLoadedChanged() { taskRoot._loadFromConfig() }
        function onTaskChanged() { taskRoot._loadFromConfig() }
    }

    Component.onCompleted: taskRoot._loadFromConfig()
    Component.onDestruction: taskRoot._persistTasks(true)

    Column {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 8

        Text {
            width: parent.width
            height: 24
            verticalAlignment: Text.AlignVCenter
            text: "TASKS"
            font.family: Theme.fontFamily
            font.pixelSize: 9
            font.letterSpacing: 1.6
            color: taskRoot._mutedText
        }

        ScrollView {
            id: scrollView
            width: parent.width
            height: parent.height - y
            clip: true
            contentWidth: availableWidth
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                width: scrollView.availableWidth
                spacing: 4

                Repeater {
                    id: taskRepeater
                    model: taskModel

                    delegate: Item {
                        id: rowItem

                        required property int index

                        width: parent.width
                        height: Math.max(editor.implicitHeight, 24)

                        Rectangle {
                            id: checkbox
                            width: 14
                            height: 14
                            radius: 4
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            color: "transparent"
                            border.width: 1
                            border.color: taskRoot._textColor
                            opacity: editor.text.trim() === "" ? 0.28 : 1.0
                        }

                        TextArea {
                            id: editor
                            anchors.left: checkbox.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: taskModel.get(rowItem.index) ? taskModel.get(rowItem.index).text : ""
                            wrapMode: TextEdit.Wrap
                            selectByMouse: true
                            persistentSelection: true
                            color: taskRoot._textColor
                            selectionColor: Qt.rgba(taskRoot._accentColor.r, taskRoot._accentColor.g, taskRoot._accentColor.b, 0.28)
                            selectedTextColor: taskRoot._textColor
                            font.family: Theme.fontFamily
                            font.pixelSize: 11
                            leftPadding: 0
                            rightPadding: 0
                            topPadding: 2
                            bottomPadding: 2
                            background: Item {}

                            onTextChanged: {
                                const existing = taskModel.get(rowItem.index)
                                if (!existing || text === existing.text)
                                    return

                                taskModel.setProperty(rowItem.index, "text", text)
                                taskRoot._ensureTrailingEmpty()
                                taskRoot._queueSave()
                            }

                            Keys.onTabPressed: function(event) {
                                event.accepted = true
                                const nextItem = taskRepeater.itemAt(rowItem.index + 1)
                                if (nextItem)
                                    nextItem.editor.forceActiveFocus()
                            }

                            Keys.onBacktabPressed: function(event) {
                                event.accepted = true
                                const prevItem = taskRepeater.itemAt(rowItem.index - 1)
                                if (prevItem)
                                    prevItem.editor.forceActiveFocus()
                            }
                        }

                        MouseArea {
                            anchors.fill: checkbox
                            enabled: editor.text.trim() !== ""
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                taskRoot._removeTaskAt(rowItem.index)
                            }
                        }
                    }
                }
            }
        }
    }
}
