import QtQuick 2.15
import Quickshell.Io 0.1
import "../lib"

Item {
    id: root
    property var moduleConfig: null

    property var  _ethIfaces:  []
    property var  _wifiIfaces: []
    property bool _vpnConnected: false
    property string _vpnServer:  ""
    property bool _vpnBusy:    false

    // ── Interface scan ────────────────────────────────────────────────────────
    Process {
        id: ifaceProc
        command: ["bash", "-c",
            "ls /sys/class/net/ | while read i; do " +
            "  state=$(cat /sys/class/net/$i/operstate 2>/dev/null || echo unknown); " +
            "  echo \"$i:$state\"; " +
            "done"]
        running: false
        stdout: StdioCollector { id: ifaceStdio }
        onExited: {
            const lines  = ifaceStdio.text.trim().split("\n")
            const eth = [], wifi = []
            for (const l of lines) {
                const p = l.split(":")
                if (p.length < 2) continue
                const name = p[0].trim(), state = p[1].trim()
                if (name === "lo") continue
                if (name.startsWith("e"))  eth.push({name, state})
                if (name.startsWith("wl")) wifi.push({name, state})
            }
            root._ethIfaces  = eth
            root._wifiIfaces = wifi
            // Fetch WiFi SSIDs
            for (const iface of wifi) {
                if (iface.state === "up") _fetchSsid(iface.name)
            }
        }
    }

    // ── WiFi SSID ─────────────────────────────────────────────────────────────
    Process {
        id: ssidProc
        property string iface: ""
        command: ["nmcli", "-g", "GENERAL.CONNECTION", "device", "show", ssidProc.iface]
        running: false
        stdout: StdioCollector { id: ssidStdio }
        onExited: {
            const ssid = ssidStdio.text.trim()
            const ifaces = root._wifiIfaces
            const idx = ifaces.findIndex(function(i) { return i.name === ssidProc.iface })
            if (idx >= 0) {
                const updated = ifaces.slice()
                updated[idx] = Object.assign({}, updated[idx], { ssid: ssid === "--" ? "" : ssid })
                root._wifiIfaces = updated
            }
        }
    }
    function _fetchSsid(iface) { ssidProc.iface = iface; ssidProc.running = true }

    // ── VPN status ────────────────────────────────────────────────────────────
    Process {
        id: vpnCheckProc
        command: ["bash", "-c",
            "state=$(cat /sys/class/net/proton0/operstate 2>/dev/null); " +
            "if [ \"$state\" = 'up' ]; then " +
            "  nmcli -t -f NAME,DEVICE connection show --active | grep ':proton0$' | cut -d: -f1; " +
            "fi"]
        running: false
        stdout: StdioCollector { id: vpnCheckStdio }
        onExited: {
            const out = vpnCheckStdio.text.trim()
            root._vpnConnected = out.length > 0
            root._vpnServer    = out.replace(/^ProtonVPN\s+/i, "")
        }
    }

    // ── VPN connect / disconnect ──────────────────────────────────────────────
    Process {
        id: vpnConnProc
        command: ["protonvpn-connect"]
        running: false
        onExited: { root._vpnBusy = false; vpnCheckProc.running = true }
    }
    Process {
        id: vpnDiscProc
        command: ["protonvpn-disconnect"]
        running: false
        onExited: { root._vpnBusy = false; vpnCheckProc.running = true }
    }

    // ── Notify helper ─────────────────────────────────────────────────────────
    Process {
        id: notifyProc
        property string msg: ""
        command: ["notify-send", "-i", "network-vpn", "-a", "ProtonVPN", "VPN", notifyProc.msg]
        running: false
    }

    Timer {
        interval: 5000; repeat: true
        running: root.visible; triggeredOnStart: true
        onTriggered: { ifaceProc.running = true; vpnCheckProc.running = true }
    }

    // ── UI ────────────────────────────────────────────────────────────────────
    Column {
        anchors { fill: parent; margins: 10 }
        spacing: 10

        // Interfaces
        Row {
            width: parent.width
            spacing: 16

            Column {
                width: (parent.width - 16) / 2
                spacing: 4
                Text { text: "ETHERNET"; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.accentColor }
                Repeater {
                    model: root._ethIfaces
                    delegate: Row {
                        spacing: 6
                        Text {
                            text: "●"; font.pixelSize: 10
                            color: modelData.state === "up" ? "#a6e3a1" : "#f38ba8"
                        }
                        Text { text: modelData.name; font.pixelSize: 10; color: Theme.textColor }
                    }
                }
                Text {
                    visible: root._ethIfaces.length === 0
                    text: "none"; font.pixelSize: 10
                    color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.4)
                }
            }

            Column {
                width: (parent.width - 16) / 2
                spacing: 4
                Text { text: "WIFI"; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.accentColor }
                Repeater {
                    model: root._wifiIfaces
                    delegate: Column {
                        spacing: 1
                        Row {
                            spacing: 6
                            Text {
                                text: "●"; font.pixelSize: 10
                                color: modelData.state === "up" ? "#a6e3a1" : "#f38ba8"
                            }
                            Text { text: modelData.name; font.pixelSize: 10; color: Theme.textColor }
                        }
                        Text {
                            visible: !!modelData.ssid
                            text: modelData.ssid || ""
                            font.pixelSize: 9; leftPadding: 16
                            color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.6)
                        }
                    }
                }
                Text {
                    visible: root._wifiIfaces.length === 0
                    text: "none"; font.pixelSize: 10
                    color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,0.4)
                }
            }
        }

        Rectangle { width: parent.width; height: 1; color: Qt.rgba(1,1,1,0.08) }

        // VPN section
        Column {
            width: parent.width
            spacing: 6

            Text { text: "VPN  ·  PROTON"; font.pixelSize: 9; font.letterSpacing: 1; color: Theme.accentColor }

            Row {
                spacing: 8
                Text {
                    text: root._vpnBusy ? "◌" : "●"; font.pixelSize: 10
                    color: root._vpnBusy ? Qt.rgba(1,1,1,0.5)
                         : root._vpnConnected ? "#a6e3a1" : "#f38ba8"
                }
                Text {
                    text: root._vpnBusy ? "Working…"
                        : root._vpnConnected ? ("Connected  ·  " + (root._vpnServer || "ProtonVPN"))
                        : "Disconnected"
                    font.pixelSize: 10; color: Theme.textColor
                }
            }

            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: (parent.width - 8) / 2; height: 26; radius: 3
                    color: root._vpnConnected ? Qt.rgba(0.647,0.89,0.631,0.25) : Qt.rgba(0.647,0.89,0.631,0.12)
                    border.width: 1
                    border.color: Qt.rgba(0.647,0.89,0.631, root._vpnConnected ? 0.5 : 0.25)
                    Text {
                        anchors.centerIn: parent
                        text: root._vpnBusy ? "CONNECTING…" : root._vpnConnected ? "CONNECTED" : "CONNECT"
                        font.pixelSize: 9; font.letterSpacing: 1
                        color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b, root._vpnConnected ? 0.5 : 1.0)
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root._vpnBusy && !root._vpnConnected
                        onClicked: {
                            root._vpnBusy = true
                            vpnConnProc.running = true
                        }
                    }
                }

                Rectangle {
                    width: (parent.width - 8) / 2; height: 26; radius: 3
                    color: Qt.rgba(0.953,0.545,0.659,0.12)
                    border.width: 1
                    border.color: Qt.rgba(0.953,0.545,0.659, root._vpnConnected ? 0.4 : 0.15)
                    Text {
                        anchors.centerIn: parent
                        text: "DISCONNECT"
                        font.pixelSize: 9; font.letterSpacing: 1
                        color: Qt.rgba(Theme.textColor.r,Theme.textColor.g,Theme.textColor.b, root._vpnConnected ? 1.0 : 0.35)
                    }
                    MouseArea {
                        anchors.fill: parent
                        enabled: !root._vpnBusy && root._vpnConnected
                        onClicked: {
                            root._vpnBusy = true
                            vpnDiscProc.running = true
                        }
                    }
                }
            }
        }
    }
}
