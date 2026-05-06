import QtQuick 2.15
import QtQuick.Effects
import QtQuick.Shapes 1.15
import QtQuick.Window 2.15
import Quickshell.Io
import Quickshell.Widgets
import "../lib"

Item {
    id: root
    property var moduleConfig: null
    property string hostControllerId: ""
    readonly property var _cfg: moduleConfig ? (moduleConfig.props || {}) : ({})
    readonly property bool _compact: _cfg.compact === true
    readonly property var _state: SystemState

    readonly property color _textColor: Theme.color(moduleConfig, "textColor", "#F8F8F2FF")
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", "#FF79C6FF")
    readonly property color _mutedText: Theme.textMuted

    readonly property int preferredHeight: _compact ? 50 : systemCol.implicitHeight
    readonly property var _packages: _state.packages || []
    readonly property bool _fetching: _state.fetching
    readonly property bool _updating: _state.updating
    readonly property bool _wifiBusy: _state.wifiBusy
    readonly property bool _vpnConnected: _state.vpnConnected
    readonly property string _vpnServer: _state.vpnServer
    readonly property string _vpnError: _state.vpnError
    readonly property bool _vpnBusy: _state.vpnBusy
    readonly property bool wifiConnected: _state.wifiConnected
    readonly property string wifiSsid: _state.wifiSsid
    property bool _stateHeld: false
    property bool compactUpdateMenuVisible: false
    property bool compactUpdateMenuOverlayHovered: false
    property real compactUpdateMenuTop: 0
    readonly property real compactUpdateMenuWidth: updateMenuMeasure.implicitWidth + 12
    readonly property real compactUpdateMenuHeight: updateMenuMeasure.implicitHeight + 12
    readonly property string compactUpdateMenuText: _packages.map(root._formatUpdatePackage).join("\n")

    readonly property var _netTiles: [
        {
            key: "vpn",
            icon: "",
            connected: root._vpnConnected,
            detail: root._vpnBusy ? "Working…" : (root._vpnConnected ? (root._vpnServer || "Connected") : (root._vpnError || "Off")),
            interactive: true,
            singleLine: true
        },
        {
            key: "wifi",
            icon: "",
            connected: root.wifiConnected,
            detail: root._wifiBusy ? "Working…" : (root.wifiConnected ? (root.wifiSsid || "Connected") : "Off"),
            interactive: true,
            singleLine: true
        }
    ]
    readonly property int _iconSlotWidth: 10

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _fmtBytes(n) {
        return _state.fmtBytes(n);
    }
    function _escapeHtml(text) {
        return String(text || "").replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }
    function _formatUpdatePackage(line) {
        const parts = String(line || "").trim().split(/\s+/);
        if (parts.length >= 4 && parts[2] === "->")
            return parts[0] + " " + parts[3];
        if (parts.length >= 2)
            return parts[0] + " " + parts[parts.length - 1];
        return String(line || "").trim();
    }
    function _formatUpdatePackageRich(line) {
        const formatted = root._formatUpdatePackage(line);
        const parts = formatted.split(/\s+/);
        if (parts.length < 2)
            return root._escapeHtml(formatted);
        const name = root._escapeHtml(parts[0]);
        const version = root._escapeHtml(parts.slice(1).join(" "));
        return name + " <span style=\"color:" + root._mutedText + ";\">" + version + "</span>";
    }

    Text {
        id: updateMenuMeasure
        visible: false
        text: root.compactUpdateMenuText
        font.family: Theme.fontFamily
        font.pixelSize: 10
    }

    function _toggleWifi() {
        _state.toggleWifi();
    }
    function _toggleVpn() {
        _state.toggleVpn();
    }
    function _hideHost() {
        if (root.hostControllerId)
            ModuleControllers.hide(root.hostControllerId);
    }
    function _packageName(entry) {
        const m = String(entry || "").match(/^(\S+)/);
        return m ? m[1] : String(entry || "");
    }
    function _fetchUpdates() {
        _state.fetchUpdates();
    }
    function _startUpdate() {
        _state.startUpdate();
        root._hideHost();
    }
    Process {
        id: nethogProc
        command: ["ghostty", "-e", "nethogs"]
        running: false
    }

    Process {
        id: btopProc
        command: ["ghostty", "-e", "btop"]
        running: false
    }

    Process {
        id: nvtopProc
        command: ["ghostty", "-e", "nvtop"]
        running: false
    }

    function _syncStateLease() {
        const shouldHold = visible;
        if (shouldHold === _stateHeld)
            return;
        _stateHeld = shouldHold;
        if (shouldHold)
            _state.retain();
        else
            _state.release();
    }

    onVisibleChanged: _syncStateLease()
    Component.onCompleted: _syncStateLease()
    Component.onDestruction: {
        if (_stateHeld)
            _state.release();
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        id: systemCol
        anchors.fill: parent
        spacing: 10

        // ── Row 2: WI-FI · VPN · UPDATE ──────────────────────────────────────
        Item {
            id: netRow
            width: parent.width
            height: root._compact ? 50 : 120
            anchors.horizontalCenter: parent.horizontalCenter

            Column {
                visible: !root._compact
                anchors.centerIn: parent
                width: Math.max(140, netRow.width - 50)
                spacing: 6

                Repeater {
                    model: root._netTiles
                    delegate: Rectangle {
                        required property var modelData
                        width: parent.width
                        height: 36
                        radius: 16
                        color: "transparent"
                        border.width: 0

                        Row {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            height: parent.height
                            spacing: 6

                            Item {
                                width: root._iconSlotWidth
                                height: parent.height

                                AccentText {
                                    anchors.centerIn: parent
                                    width: root._iconSlotWidth
                                    text: modelData.icon
                                    fontFamily: "Symbols Nerd Font"
                                    fontPixelSize: 14
                                    color: tileMA.containsMouse ? root._textColor : root._mutedText
                                    backgroundVisible: tileMA.containsMouse
                                    horizontalAlignment: Text.AlignHCenter
                                    radius: 6
                                    paddingX: 0
                                    paddingY: 0
                                    Behavior on color {
                                        ColorAnimation {
                                            duration: 150
                                        }
                                    }
                                }
                            }

                            Text {
                                width: parent.width - root._iconSlotWidth - parent.spacing
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.detail
                                font.family: Theme.fontFamily
                                font.pixelSize: 9
                                font.bold: true
                                color: root._textColor
                                elide: Text.ElideRight
                            }
                        }

                        MouseArea {
                            id: tileMA
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: modelData.interactive
                            cursorShape: modelData.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (modelData.key === "wifi")
                                    root._toggleWifi();
                                else if (modelData.key === "vpn")
                                    root._toggleVpn();
                            }
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 36
                    radius: 16
                    color: "transparent"

                    Row {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        height: parent.height
                        spacing: 6

                        Item {
                            width: root._iconSlotWidth
                            height: parent.height

                            AccentText {
                                anchors.centerIn: parent
                                width: root._iconSlotWidth
                                text: ""
                                fontFamily: "Symbols Nerd Font"
                                fontPixelSize: 14
                                color: updateMA.containsMouse ? root._textColor : root._mutedText
                                backgroundVisible: updateMA.containsMouse
                                horizontalAlignment: Text.AlignHCenter
                                radius: 6
                                paddingX: 0
                                paddingY: 0
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 150
                                    }
                                }
                            }
                        }

                        Text {
                            width: parent.width - root._iconSlotWidth - parent.spacing
                            anchors.verticalCenter: parent.verticalCenter
                            text: (root._fetching || root._updating) ? "…" : (root._packages.length === 0 ? "CLEAN" : (root._packages.length + " PKGs"))
                            font.family: Theme.fontFamily
                            font.pixelSize: 9
                            font.bold: true
                            color: root._textColor
                            elide: Text.ElideRight
                        }
                    }

                    MouseArea {
                        id: updateMA
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root._startUpdate()
                        onPressAndHold: root._fetchUpdates()
                    }
                }
            }

            Column {
                visible: root._compact
                anchors.centerIn: parent
                width: parent.width
                spacing: 2

                Repeater {
                    model: [
                        {
                            icon: "",
                            text: root._vpnBusy ? "VPN …" : (root._vpnConnected ? "VPN ON" : "VPN OFF"),
                            action: "vpn"
                        },
                        {
                            icon: "",
                            text: root._wifiBusy ? "WIFI …" : (root.wifiConnected ? "WIFI ON" : "WIFI OFF"),
                            action: "wifi"
                        },
                        {
                            icon: "",
                            text: (root._fetching || root._updating) ? "… PKGS" : (root._packages.length === 0 ? "OK PKGS" : (root._packages.length + " PKGS")),
                            action: "update"
                        }
                    ]

                    delegate: Item {
                        required property var modelData
                        readonly property bool _isUpdate: modelData.action === "update"
                        readonly property bool _showUpdateMenu: _isUpdate && root._packages.length > 0 && !root._fetching && !root._updating && (compactMA.containsMouse || root.compactUpdateMenuOverlayHovered)
                        width: parent.width
                        height: 14

                        function _syncUpdateMenu() {
                            if (!_isUpdate)
                                return;
                            root.compactUpdateMenuVisible = _showUpdateMenu;
                            if (!_showUpdateMenu)
                                return;
                            const pos = mapToItem(root, 0, 0);
                            root.compactUpdateMenuTop = pos.y + compactText.y + compactText.height;
                        }

                        Item {
                            id: compactIconSlot
                            width: root._iconSlotWidth
                            height: parent.height
                            anchors.left: parent.left
                            anchors.leftMargin: 4
                            anchors.verticalCenter: parent.verticalCenter

                            AccentText {
                                anchors.centerIn: parent
                                width: root._iconSlotWidth
                                text: modelData.icon
                                fontFamily: "Symbols Nerd Font"
                                fontPixelSize: 11
                                color: compactMA.containsMouse ? root._textColor : root._mutedText
                                backgroundVisible: compactMA.containsMouse
                                horizontalAlignment: Text.AlignHCenter
                                radius: 6
                                paddingX: 0
                                paddingY: 0
                                Behavior on color {
                                    ColorAnimation {
                                        duration: 150
                                    }
                                }
                            }
                        }

                        Text {
                            id: compactText
                            anchors.left: compactIconSlot.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: modelData.text
                            font.family: Theme.fontFamily
                            font.pixelSize: 8
                            font.bold: true
                            color: root._textColor
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideNone
                        }

                        MouseArea {
                            id: compactMA
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (modelData.action === "wifi")
                                    root._toggleWifi();
                                else if (modelData.action === "vpn")
                                    root._toggleVpn();
                                else if (modelData.action === "update")
                                    root._startUpdate();
                            }
                            onPressAndHold: {
                                if (modelData.action === "update")
                                    root._fetchUpdates();
                            }
                        }

                        Component.onCompleted: _syncUpdateMenu()
                        on_ShowUpdateMenuChanged: _syncUpdateMenu()
                        onXChanged: _syncUpdateMenu()
                        onYChanged: _syncUpdateMenu()
                    }
                }
            }
        }
    }
}
