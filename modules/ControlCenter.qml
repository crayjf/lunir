import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../lib"

PanelWindow {
    id: root

    readonly property string hostControllerId: "control-center"
    readonly property int _sidebarWidth: 420
    readonly property int _outerMarginX: {
        const value = Number(Config.controlCenter.marginX)
        return isNaN(value) ? 0 : Math.max(0, Math.round(value))
    }
    readonly property int _outerMarginY: {
        const value = Number(Config.controlCenter.marginY)
        return isNaN(value) ? 0 : Math.max(0, Math.round(value))
    }

    readonly property color _textColor: Theme.text
    readonly property color _accentColor: Theme.accent
    readonly property color _mutedText: Theme.textMuted
    readonly property color _softText: Theme.textMuted
    readonly property color _panelColor: Theme.surface
    readonly property int _sectionGap: 12
    readonly property var _days: ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
    readonly property var _months: ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
                                    "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]

    property string weekdayText: ""
    property string dateText: ""
    property string timeText: ""

    // ── Launcher-in-header ────────────────────────────────────────────────────
    readonly property var _desktopApps: DesktopEntries.applications.values
    readonly property var _launcherCfg: ModuleRegistry.sidebarConfig("launcher")
    readonly property string _terminalCommand: (_launcherCfg && _launcherCfg.props) ? (_launcherCfg.props.terminalCommand || "ghostty") : "ghostty"
    readonly property string _iconTheme: (_launcherCfg && _launcherCfg.props) ? (_launcherCfg.props.iconTheme || "") : ""
    readonly property var _iconThemePaths: {
        const cfg = (_launcherCfg && _launcherCfg.props) ? _launcherCfg.props : {}
        if (Array.isArray(cfg.iconThemePaths) && cfg.iconThemePaths.length > 0)
            return cfg.iconThemePaths
        const home = Quickshell.env("HOME") || ""
        return [home + "/.icons", home + "/.local/share/icons", "/usr/local/share/icons", "/usr/share/icons"]
    }
    property string _searchQuery: ""
    property var _searchResults: []
    property var _iconMap: ({})
    readonly property bool _searching: _searchQuery.length > 0
    readonly property var _topResult: _searchResults.length > 0 ? _searchResults[0] : null
    readonly property string _ghostSuffix: {
        if (!_topResult || !_searching) return ""
        const name = _topResult.name || ""
        const q = _searchQuery
        if (name.toLowerCase().startsWith(q.toLowerCase()))
            return name.substring(q.length)
        return ""
    }

    aboveWindows: true
    focusable: true
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.namespace: Config.namespaceFor("control-center")
    anchors {
        top: true
        bottom: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    screen: Quickshell.screens[0]

    margins {
        top: root._outerMarginY
        bottom: root._outerMarginY
        right: _animStyle === "Move"
            ? Math.round(root._outerMarginX - (1.0 - animProgress) * _sidebarWidth)
            : root._outerMarginX
    }

    implicitWidth: _sidebarWidth
    visible: false

    property real animProgress: 0.0
    Behavior on animProgress { NumberAnimation { duration: Config.controlCenter.animationTime ?? 180; easing.type: Easing.OutCubic } }
    onAnimProgressChanged: { if (animProgress <= 0.0) visible = false }

    readonly property string _animStyle: Config.controlCenter.animationStyle || "Move"
    readonly property real _contentOpacity: (_animStyle === "Fade" || _animStyle === "Blur") ? animProgress : 1.0

    function show() {
        visible = true
        animProgress = 1.0
        resetTransientState()
        searchInput.text = ""
        focusItem.forceActiveFocus()
    }

    function hide() {
        animProgress = 0.0
    }

    function _tickClock() {
        const now = new Date()
        const h = String(now.getHours()).padStart(2, "0")
        const m = String(now.getMinutes()).padStart(2, "0")
        weekdayText = _days[now.getDay()]
        dateText = now.getDate() + " " + _months[now.getMonth()]
        timeText = h + ":" + m
    }

    function resetTransientState() {
        if (calendarSection.moduleItem && calendarSection.moduleItem._resetDisplayDay)
            calendarSection.moduleItem._resetDisplayDay()
        if (notificationsSlot.moduleItem && notificationsSlot.moduleItem._resetStack)
            notificationsSlot.moduleItem._resetStack()
    }
    function _wallpaperModule() {
        return wallpaperSlot.moduleItem
    }
    function _moveWallpaper(step) {
        const wallpaper = root._wallpaperModule()
        if (wallpaper && wallpaper._selectRelative) wallpaper._selectRelative(step)
    }
    function _applyWallpaperSelection() {
        const wallpaper = root._wallpaperModule()
        if (wallpaper && wallpaper._applySelected) wallpaper._applySelected()
    }
    function _beginLauncherInput(text) {
        searchInput.forceActiveFocus()
        if (text && text.length > 0) {
            searchInput.text = text
            searchInput.cursorPosition = searchInput.text.length
        }
    }
    function _isLauncherTextEvent(event) {
        if (!event || !event.text || event.text.length === 0) return false
        if (event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier)) return false
        const ch = event.text
        return ch >= " "
    }

    function _score(name, query) {
        const q = query.toLowerCase(), n = name.toLowerCase()
        if (n === q) return 100
        if (n.startsWith(q)) return 80
        if (n.includes(q)) return 60
        let i = 0
        for (const ch of n) { if (ch === q[i]) i++; if (i === q.length) return 20 }
        return -1
    }

    function _filter(query) {
        const q = query.trim()
        const scored = root._desktopApps
            .map(function(app) { return { app: app, score: q ? root._score(app.name || "", q) : 50 } })
            .filter(function(e) { return e.score >= 0 })
            .sort(function(a, b) { return b.score !== a.score ? b.score - a.score : (a.app.name || "").localeCompare(b.app.name || "") })
        root._searchResults = scored.slice(0, 1).map(function(e) { return e.app })
    }

    function _launchTop() {
        const app = root._topResult
        if (!app) return
        const ctx = app.runInTerminal
            ? { command: [root._terminalCommand, "-e"].concat(app.command || []), workingDirectory: app.workingDirectory || "" }
            : { command: app.command || [], workingDirectory: app.workingDirectory || "" }
        if (!ctx.command || ctx.command.length === 0) return
        Quickshell.execDetached(ctx)
        root.hide()
    }

    function _shellQuote(v) { return "'" + String(v).replace(/'/g, "'\\''") + "'" }

    function _resolveTopIcon() {
        const app = root._topResult
        if (!app || !_searching || !root._iconTheme) { root._iconMap = ({}); return }
        const iconName = String((app && app.icon) || "")
        if (!iconName || iconName.indexOf("/") !== -1) { root._iconMap = ({}); return }
        const quotedRoots = root._iconThemePaths.filter(function(p) { return !!p }).map(root._shellQuote).join(" ")
        const quotedTheme = root._shellQuote(root._iconTheme)
        const quotedName = root._shellQuote(iconName)
        iconResolveProc._cmd = `
theme=${quotedTheme}
roots=(${quotedRoots})
icon_name=${quotedName}
for dir in "\${roots[@]}"; do
    [ -d "$dir/$theme" ] || continue
    found=$(find "$dir/$theme" -type f \\( -iname "$icon_name.svg" -o -iname "$icon_name.png" -o -iname "$icon_name.xpm" \\) 2>/dev/null | sort | head -n 1)
    if [ -n "$found" ]; then printf '%s\\t%s\\n' "$icon_name" "$found"; exit 0; fi
done`
        iconResolveProc.running = true
    }

    function _iconSource(iconName) {
        if (!iconName) return ""
        if (iconName.indexOf("/") !== -1) return iconName
        if (root._iconMap[iconName]) return root._iconMap[iconName]
        if (iconName === "btop") return "/usr/share/icons/hicolor/48x48/apps/btop.png"
        return Quickshell.iconPath(iconName, true)
    }

    component ModuleSlot: Item {
        id: slot

        property string moduleType: ""
        property var extraProps: ({})
        property string hostControllerId: ""
        readonly property var moduleConfig: ModuleRegistry.sidebarConfig(moduleType, extraProps)
        readonly property var moduleItem: moduleLoader.item

        function _applyLoaderProps() {
            const item = moduleLoader.item
            if (!item) return
            item.moduleConfig = moduleConfig
            if (hostControllerId && item.hostControllerId !== undefined)
                item.hostControllerId = hostControllerId
        }

        Loader {
            id: moduleLoader
            anchors.fill: parent
            source: ModuleRegistry.url(slot.moduleType)
            onLoaded: slot._applyLoaderProps()
        }

        onModuleConfigChanged: _applyLoaderProps()
        onHostControllerIdChanged: _applyLoaderProps()
    }

    Process {
        id: iconResolveProc
        property string _cmd: ""
        command: ["bash", "-c", iconResolveProc._cmd]
        running: false
        stdout: StdioCollector { id: iconResolveStdio }
        onExited: {
            const map = {}
            for (const line of iconResolveStdio.text.split("\n")) {
                if (!line) continue
                const tab = line.indexOf("\t")
                if (tab < 0) continue
                const name = line.substring(0, tab)
                const path = line.substring(tab + 1)
                if (name && path) map[name] = path
            }
            root._iconMap = map
        }
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() { if (root._searching) root._filter(root._searchQuery) }
    }

    on_SearchResultsChanged: root._resolveTopIcon()

    Timer {
        interval: 1000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: root._tickClock()
    }

    Item {
        id: contentContainer
        width: parent.width
        height: parent.height
        opacity: root._contentOpacity
        layer.enabled: root._animStyle === "Blur"
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1.0 - root.animProgress
            blurMax: 32
        }

    Rectangle {
        anchors.fill: parent
        radius: Theme.radiusLarge
        color: Theme.background

        Item {
            id: focusItem
            anchors.fill: parent
            focus: true
            Keys.onLeftPressed: (event) => {
                root._moveWallpaper(-1)
                event.accepted = true
            }
            Keys.onRightPressed: (event) => {
                root._moveWallpaper(1)
                event.accepted = true
            }
            Keys.onReturnPressed: (event) => {
                root._applyWallpaperSelection()
                event.accepted = true
            }
            Keys.onEnterPressed: (event) => {
                root._applyWallpaperSelection()
                event.accepted = true
            }
            Keys.onEscapePressed: (event) => {
                root.hide()
                event.accepted = true
            }
            Keys.onPressed: (event) => {
                if (!event.accepted && root._isLauncherTextEvent(event)) {
                    root._beginLauncherInput(event.text)
                    event.accepted = true
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: parent.radius
            color: Theme.background
        }

        RainbowBorder {
            anchors.fill: parent
            visible: false
            radius: parent.radius
            lineWidth: Theme.borderWidth
        }
    }

    Rectangle {
        id: headerPanel
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 14
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        height: 34
        radius: Theme.radiusLarge
        color: "transparent"

        Item {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12

            // Default header texts — fade out while searching
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: root.dateText
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
                color: root._textColor
                opacity: root._searching ? 0.0 : 1.0
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            Text {
                anchors.centerIn: parent
                text: root.weekdayText
                font.family: Theme.fontFamily
                font.pixelSize: 10
                font.letterSpacing: 1.6
                color: root._softText
                opacity: root._searching ? 0.0 : 1.0
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: root.timeText
                font.family: Theme.fontFamily
                font.pixelSize: 16
                font.bold: true
                color: root._textColor
                opacity: root._searching ? 0.0 : 1.0
                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
            }

            // Search: auto-sized input + ghost text in a row so ghost never drifts
            Item {
                anchors.left: parent.left
                anchors.right: searchIconSlot.left
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                height: searchInput.height
                clip: true

                Row {
                    anchors.verticalCenter: parent.verticalCenter

                    TextInput {
                        id: searchInput
                        width: Math.max(1, contentWidth)
                        font.family: Theme.fontFamily
                        font.pixelSize: 16
                        font.bold: true
                        color: root._textColor
                        cursorVisible: false
                        cursorDelegate: Item {}
                        selectionColor: Qt.rgba(root._accentColor.r, root._accentColor.g, root._accentColor.b, 0.3)
                        selectedTextColor: root._textColor
                        onTextChanged: { root._searchQuery = text; root._filter(text) }
                        Keys.onReturnPressed: root._launchTop()
                        Keys.onEscapePressed: { if (text.length > 0) text = ""; else root.hide() }
                    }

                    Text {
                        visible: root._searching && root._ghostSuffix !== ""
                        text: root._ghostSuffix
                        font: searchInput.font
                        color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.28)
                    }
                }
            }

            // App icon slot — fades in on the right when searching
            Item {
                id: searchIconSlot
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: root._searching ? 22 : 0
                height: 22
                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                clip: true

                Image {
                    id: searchResultIcon
                    anchors.centerIn: parent
                    width: 22; height: 22
                    source: root._topResult ? root._iconSource(root._topResult.icon || "") : ""
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    mipmap: true
                    smooth: true
                    visible: source !== "" && status === Image.Ready
                }
            }
        }
    }

    Item {
        id: contentArea
        anchors.top: perfSection.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.topMargin: 0
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.bottomMargin: 14

        ScrollView {
            id: upperScroll
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            height: Math.max(0, Math.min(
                upperContent.implicitHeight,
                contentArea.height
                    - wallpaperSection.height
                    - (garminSlot.moduleItem ? garminSlot.moduleItem.preferredHeight : 280)
                    - quoteSection.height
                    - notificationsSection.height
                    - (root._sectionGap * 4)
            ))
            clip: true
            ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
            ScrollBar.vertical.policy: ScrollBar.AsNeeded

            Column {
                id: upperContent
                width: upperScroll.availableWidth
                spacing: root._sectionGap

                Item {
                    id: mediaSection
                    width: parent.width
                    height: 140

                    ModuleSlot {
                        anchors.fill: parent
                        moduleType: "media"
                    }
                }

                Item {
                    width: parent.width
                    height: weatherSection.height + 6 + calendarFrame.height

                    Item {
                        id: weatherSection
                        anchors.top: parent.top
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 100

                        ModuleSlot {
                            anchors.fill: parent
                            moduleType: "weather"
                        }
                    }

                    Item {
                        id: calendarFrame
                        anchors.top: weatherSection.bottom
                        anchors.topMargin: 6
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: 210

                        ModuleSlot {
                            id: calendarSection
                            anchors.fill: parent
                            moduleType: "calendar"
                        }
                    }
                }
            }
        }

        Item {
            id: notificationsSection
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: upperScroll.bottom
            anchors.topMargin: root._sectionGap
            height: 50

            ModuleSlot {
                id: notificationsSlot
                anchors.fill: parent
                moduleType: "notifications"
            }
        }

                Item {
                    id: garminSection
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: notificationsSection.bottom
                    anchors.topMargin: root._sectionGap
                    anchors.bottom: quoteSection.top
                    anchors.bottomMargin: root._sectionGap

                    ModuleSlot {
                        id: garminSlot
                        anchors.fill: parent
                        moduleType: "garmin"
                    }
                }

                Item {
                    id: quoteSection
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: wallpaperSection.top
                    anchors.bottomMargin: 4
                    height: quoteSlot.moduleItem ? quoteSlot.moduleItem.preferredHeight : 90

                    ModuleSlot {
                        id: quoteSlot
                        anchors.fill: parent
                        moduleType: "quote"
                    }
                }

                Item {
                    id: wallpaperSection
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 150

                    ModuleSlot {
                        id: wallpaperSlot
                        anchors.fill: parent
                        moduleType: "wallpaper"
                    }
                }
    }

    Item {
        id: perfSection
        anchors.top: headerPanel.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: 0
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        height: systemSlot.moduleItem ? systemSlot.moduleItem.preferredHeight : 252

        ModuleSlot {
            id: systemSlot
            anchors.fill: parent
            moduleType: "system"
            hostControllerId: root.hostControllerId
        }
    }

    } // contentContainer

    // Border rendered outside contentContainer so it is unaffected by opacity/blur animations
    Rectangle {
        anchors.fill: contentContainer
        radius: Theme.radiusLarge
        color: "transparent"
        border.width: Theme.borderWidth
        border.color: Theme.border
        visible: !Theme.borderIsRainbow || Theme.borderWidth <= 0
    }
    RainbowBorder {
        anchors.fill: contentContainer
        visible: Theme.borderIsRainbow && Theme.borderWidth > 0
        radius: Theme.radiusLarge
        lineWidth: Theme.borderWidth
    }

    Component.onCompleted: {
        ModuleControllers.register(root.hostControllerId, {
            "show": function() { root.show() },
            "hide": function() { root.hide() },
            "toggle": function() { if (root.visible) root.hide(); else root.show() },
            "isVisible": function() { return root.visible }
        })
    }

    Component.onDestruction: {
        ModuleControllers.unregister(root.hostControllerId)
    }
}
