import QtQuick 2.15
import Quickshell 0.1
import Quickshell.Wayland 0.1
import "../lib"

// Transient notification popup (top-left, auto-dismisses after 5 s).
// Shown by NotificationService when a new notification arrives.
PanelWindow {
    id: win

    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: "lunir-qs"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    anchors { top: true; left: true }
    exclusionMode: ExclusionMode.Normal
    color: "transparent"

    visible: false

    readonly property var _cfg: Config.modules.find(function(m) { return m.type === "notifications" }) || null

    margins {
        top:  _cfg ? (_cfg.y ?? 0) : 0
        left: _cfg ? (_cfg.x ?? 0) : 0
    }

    readonly property int _w: _cfg ? (_cfg.width ?? 520) : 520

    implicitWidth:  _w
    implicitHeight: contentCol.implicitHeight + 16

    property real fadeOpacity: 0.0
    Behavior on fadeOpacity { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
    onFadeOpacityChanged: { if (fadeOpacity <= 0.0) visible = false }

    // ── Content ───────────────────────────────────────────────────────────────
    Rectangle {
        width: win._w
        height: contentCol.implicitHeight + 16
        color: Qt.rgba(Theme.widgetBackground.r, Theme.widgetBackground.g, Theme.widgetBackground.b,
                       Theme.widgetBackground.a * Theme.widgetOpacity * win.fadeOpacity)
        radius: Theme.widgetBorderRadius
        border.color: Theme.widgetBorderColor
        border.width: Theme.widgetBorderWidth

        Column {
            id: contentCol
            anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
            spacing: 3

            Text {
                id: appText
                text: ""
                font.pixelSize: 10
                font.letterSpacing: 1.5
                color: Theme.accentColor
                visible: text.length > 0
            }
            Text {
                id: summaryText
                text: ""
                font.pixelSize: 13
                color: Theme.textColor
                wrapMode: Text.WordWrap
                width: parent.width
                visible: text.length > 0
            }
            Text {
                id: bodyText
                text: ""
                font.pixelSize: 11
                color: Qt.rgba(
                    Theme.textColor.r, Theme.textColor.g,
                    Theme.textColor.b, 0.7)
                wrapMode: Text.WordWrap
                width: parent.width
                visible: text.length > 0
            }
        }
    }

    // ── Dismiss timer ─────────────────────────────────────────────────────────
    Timer {
        id: dismissTimer
        interval: 5000
        repeat: false
        onTriggered: win.fadeOpacity = 0.0
    }

    // ── Show ──────────────────────────────────────────────────────────────────
    function showNotification(n) {
        if (ModuleControllers.isVisible("overlay")) return
        dismissTimer.restart()
        appText.text     = (n.appName || n.app || "").toUpperCase()
        summaryText.text = n.summary || ""
        bodyText.text    = n.body    || ""
        visible      = true
        fadeOpacity  = 1.0
    }

    // React to new notifications from NotificationService
    Connections {
        target: NotificationService
        function onNotificationAdded(n) { win.showNotification(n) }
    }
}
