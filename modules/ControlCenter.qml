import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../lib"

PanelWindow {
    id: root

    readonly property string hostControllerId: "control-center"
    readonly property int _width: 880
    readonly property int _columnGap: 12
    readonly property int _calendarTopGap: 4
    readonly property int _columnWidth: Math.max(0, Math.floor((columns.width - root._columnGap) / 2))
    readonly property int _centerOffsetX: {
        const screenWidth = screen ? screen.width : 0
        return Math.max(0, Math.round((screenWidth - implicitWidth) / 2))
    }
    readonly property int _centerOffsetY: {
        const screenHeight = screen ? screen.height : 0
        return Math.max(0, Math.round((screenHeight - implicitHeight) / 2))
    }

    readonly property color _textColor: Theme.text
    readonly property color _accentColor: Theme.accent
    readonly property color _softText: Theme.textMuted
    readonly property int _sectionGap: 12
    readonly property int _headerColumnsGap: 8
    readonly property int _headerLabelGap: 12
    readonly property int _rightColumnTopMargin: 8
    readonly property int _wallpaperTopGap: 4
    readonly property int _wallpaperBottomGap: 8

    readonly property var _launcherCfg: ModuleRegistry.panelConfig("launcher")
    readonly property string _terminalCommand: (_launcherCfg && _launcherCfg.props) ? (_launcherCfg.props.terminalCommand || "ghostty") : "ghostty"
    readonly property string _iconTheme: (_launcherCfg && _launcherCfg.props) ? (_launcherCfg.props.iconTheme || "") : ""
    readonly property var _iconThemePaths: {
        const cfg = (_launcherCfg && _launcherCfg.props) ? _launcherCfg.props : {}
        if (Array.isArray(cfg.iconThemePaths) && cfg.iconThemePaths.length > 0)
            return cfg.iconThemePaths
        const home = Quickshell.env("HOME") || ""
        return [home + "/.icons", home + "/.local/share/icons", "/usr/local/share/icons", "/usr/share/icons"]
    }

    readonly property string _backdropMode: Config.backdrop.mode || "blur"
    readonly property real _backdropBlur: Config.backdrop.blur ?? 1.0
    readonly property int _backdropBlurMax: Config.backdrop.blurMax ?? 64
    readonly property real _backdropSaturation: Config.backdrop.saturation ?? -0.15
    readonly property string _launcherFallbackIcon: Quickshell.iconPath("system-search", true) || Quickshell.iconPath("edit-find", true) || ""
    readonly property string _launcherFallbackGlyph: "⌕"
    readonly property string _animStyle: Config.controlCenter.animationStyle || "Move"
    readonly property real _contentOpacity: (_animStyle === "Fade" || _animStyle === "Blur") ? animProgress : 1.0
    readonly property var _days: ["SUNDAY", "MONDAY", "TUESDAY", "WEDNESDAY", "THURSDAY", "FRIDAY", "SATURDAY"]
    readonly property var _months: ["JANUARY", "FEBRUARY", "MARCH", "APRIL", "MAY", "JUNE",
                                    "JULY", "AUGUST", "SEPTEMBER", "OCTOBER", "NOVEMBER", "DECEMBER"]
    readonly property var _desktopApps: DesktopEntries.applications.values
    property var _preferredScreen: Quickshell.screens[0]

    property string weekdayText: ""
    property string dateText: ""
    property string timeText: ""
    property bool _resolvingTopIcon: false
    property bool _iconThemeIndexed: false
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
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
    WlrLayershell.namespace: Config.namespaceFor("control-center")
    anchors {
        left: true
        top: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    screen: Quickshell.screens[0]

    margins {
        left: root._centerOffsetX
        top: root._centerOffsetY
    }

    implicitWidth: root._width
    implicitHeight: {
        const garminH = garminSlot.moduleItem ? garminSlot.moduleItem.preferredHeight : 300
        const quoteH = quoteSlot.moduleItem ? quoteSlot.moduleItem.preferredHeight : 90
        const wallpaperH = wallpaperSlot.moduleItem ? wallpaperSlot.moduleItem.preferredHeight : 120
        const calendarH = calendarSlot.moduleItem ? calendarSlot.moduleItem.preferredHeight : 420
        const bodyH = topSection.height + root._calendarTopGap + calendarH + root._wallpaperTopGap + wallpaperH + root._wallpaperBottomGap
        return Math.round(14 + bodyH + 6)
    }
    visible: false

    property real animProgress: 0.0
    Behavior on animProgress { NumberAnimation { duration: Config.controlCenter.animationTime ?? 180; easing.type: Easing.OutCubic } }
    onAnimProgressChanged: {
        if (animProgress <= 0.0)
            visible = false
    }

    function _screenForOutputName(name) {
        if (!name) return null
        for (const candidate of Quickshell.screens) {
            if (!candidate) continue
            if (candidate.name === name) return candidate
        }
        return null
    }

    function _showOnScreen(targetScreen) {
        if (targetScreen)
            root.screen = targetScreen
        if (targetScreen)
            root._preferredScreen = targetScreen
        visible = true
        animProgress = 1.0
        resetTransientState()
        searchInput.text = ""
        focusItem.forceActiveFocus()
        Qt.callLater(function() { focusItem.forceActiveFocus() })
    }

    function show() {
        root._showOnScreen(root._preferredScreen || root.screen || Quickshell.screens[0])
        focusedOutputProc.running = false
        focusedOutputProc.running = true
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
        SelectedDay.reset()
        if (calendarSlot.moduleItem && calendarSlot.moduleItem._resetDisplayDay)
            calendarSlot.moduleItem._resetDisplayDay()
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

    function _deleteWallpaperSelection() {
        const wallpaper = root._wallpaperModule()
        if (wallpaper && wallpaper._deleteSelected) wallpaper._deleteSelected()
    }

    function _dismissCurrentNotification() {
        const notifications = notificationsSlot.moduleItem
        if (notifications && notifications.dismissCurrentNotification)
            notifications.dismissCurrentNotification()
    }

    function _requestNewQuote() {
        const quote = quoteSlot.moduleItem
        if (quote && quote._requestNewQuote)
            quote._requestNewQuote()
    }

    function _triggerSystemUpdate() {
        const system = systemSlot.moduleItem
        if (system && system._startUpdate)
            system._startUpdate()
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
        return event.text >= " "
    }

    function _score(name, query) {
        const q = query.toLowerCase()
        const n = name.toLowerCase()
        if (n === q) return 100
        if (n.startsWith(q)) return 80
        if (n.includes(q)) return 60
        let i = 0
        for (const ch of n) {
            if (ch === q[i]) i++
            if (i === q.length) return 20
        }
        return -1
    }

    function _filter(query) {
        const q = query.trim()
        if (!q) {
            root._searchResults = []
            root._resolvingTopIcon = false
            return
        }
        if (root._iconTheme && !root._iconThemeIndexed && !iconIndexProc.running)
            root._indexThemeIcons()
        const scored = root._desktopApps
            .map(function(app) { return { app: app, score: root._score(app.name || "", q) } })
            .filter(function(entry) { return entry.score >= 0 })
            .sort(function(a, b) { return b.score !== a.score ? b.score - a.score : (a.app.name || "").localeCompare(b.app.name || "") })
        root._searchResults = scored.slice(0, 1).map(function(entry) { return entry.app })
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

    function _shellQuote(v) {
        return "'" + String(v).replace(/'/g, "'\\''") + "'"
    }

    function _resolveTopIcon() {
        const app = root._topResult
        if (!app || !_searching || !root._iconTheme) {
            root._resolvingTopIcon = false
            return
        }
        const iconName = String((app && app.icon) || "")
        if (!iconName || iconName.indexOf("/") !== -1) {
            root._resolvingTopIcon = false
            return
        }
        if (!root._iconThemeIndexed && !iconIndexProc.running)
            root._indexThemeIcons()
        if (root._iconMap[iconName]) {
            root._resolvingTopIcon = false
            return
        }
        root._resolvingTopIcon = true
        const quotedRoots = root._iconThemePaths.filter(function(path) { return !!path }).map(root._shellQuote).join(" ")
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

    function _indexThemeIcons() {
        if (!root._iconTheme) {
            root._iconThemeIndexed = false
            root._iconMap = ({})
            return
        }
        root._iconThemeIndexed = false
        const quotedRoots = root._iconThemePaths.filter(function(path) { return !!path }).map(root._shellQuote).join(" ")
        const quotedTheme = root._shellQuote(root._iconTheme)
        iconIndexProc._cmd = `
theme=${quotedTheme}
roots=(${quotedRoots})
for dir in "\${roots[@]}"; do
    [ -d "$dir/$theme" ] || continue
    find "$dir/$theme" -type f \\( -iname '*.svg' -o -iname '*.png' -o -iname '*.xpm' \\) 2>/dev/null
done | sort | while IFS= read -r path; do
    file=$(basename "$path")
    name=\${file%.*}
    printf '%s\\t%s\\n' "$name" "$path"
done`
        iconIndexProc.running = true
    }

    function _iconSource(iconName) {
        if (!iconName) return ""
        if (iconName.indexOf("/") !== -1) return ""
        if (root._iconMap[iconName]) return root._iconMap[iconName]
        return ""
    }

    component ModuleSlot: Item {
        id: slot

        property string moduleType: ""
        property var extraProps: ({})
        property string hostControllerId: ""
        property bool eager: false
        property bool keepWarm: true
        property bool _loadedOnce: false
        readonly property var moduleConfig: ModuleRegistry.panelConfig(moduleType, extraProps)
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
            active: slot.eager || root.visible || (slot.keepWarm && slot._loadedOnce)
            source: ModuleRegistry.url(slot.moduleType)
            onLoaded: {
                slot._loadedOnce = true
                slot._applyLoaderProps()
            }
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
            const map = Object.assign({}, root._iconMap)
            for (const line of iconResolveStdio.text.split("\n")) {
                if (!line) continue
                const tab = line.indexOf("\t")
                if (tab < 0) continue
                const name = line.substring(0, tab)
                const path = line.substring(tab + 1)
                if (name && path) map[name] = path
            }
            root._iconMap = map
            root._resolvingTopIcon = false
        }
    }

    Process {
        id: iconIndexProc
        property string _cmd: ""
        command: ["bash", "-c", iconIndexProc._cmd]
        running: false
        stdout: StdioCollector { id: iconIndexStdio }
        onExited: {
            const map = {}
            for (const line of iconIndexStdio.text.split("\n")) {
                if (!line) continue
                const tab = line.indexOf("\t")
                if (tab < 0) continue
                const name = line.substring(0, tab)
                const path = line.substring(tab + 1)
                if (name && path && !map[name]) map[name] = path
            }
            root._iconMap = map
            root._iconThemeIndexed = true
            if (root._searching)
                root._resolveTopIcon()
        }
    }

    Process {
        id: focusedOutputProc
        command: ["niri", "msg", "-j", "focused-output"]
        running: false
        stdout: StdioCollector { id: focusedOutputStdio }
        onExited: {
            let targetScreen = Quickshell.screens[0]
            try {
                const data = JSON.parse(focusedOutputStdio.text.trim())
                const resolved = root._screenForOutputName(data && data.name ? String(data.name) : "")
                if (resolved)
                    targetScreen = resolved
            } catch (_) {}
            root._preferredScreen = targetScreen
            if (root.visible && root.screen !== targetScreen)
                root.screen = targetScreen
        }
    }

    Connections {
        target: DesktopEntries.applications
        function onValuesChanged() {
            if (root._searching)
                root._filter(root._searchQuery)
        }
    }

    on_IconThemeChanged: {
        root._iconThemeIndexed = false
        root._iconMap = ({})
        if (root._searching)
            root._indexThemeIcons()
    }
    on_IconThemePathsChanged: {
        root._iconThemeIndexed = false
        root._iconMap = ({})
        if (root._searching)
            root._indexThemeIcons()
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

        ClippingRectangle {
            anchors.fill: parent
            radius: Theme.radiusLarge
            color: "transparent"

            DesktopBackdrop {
                id: wallpaperBackdrop
                anchors.fill: parent
                screen: root.screen || Quickshell.screens[0]
                sourceX: root._centerOffsetX
                sourceY: root._centerOffsetY
                mode: root._backdropMode
                blur: root._backdropBlur
                blurMax: root._backdropBlurMax
                saturation: root._backdropSaturation
            }

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
                Keys.onUpPressed: (event) => {
                    root._requestNewQuote()
                    event.accepted = true
                }
                Keys.onDownPressed: (event) => {
                    root._requestNewQuote()
                    event.accepted = true
                }
                Keys.onReturnPressed: (event) => {
                    root._applyWallpaperSelection()
                    event.accepted = true
                }
                Keys.onEscapePressed: (event) => {
                    root.hide()
                    event.accepted = true
                }
                Keys.onPressed: (event) => {
                    if (!event.accepted && event.key === Qt.Key_C && (event.modifiers & Qt.ControlModifier)) {
                        root._triggerSystemUpdate()
                        event.accepted = true
                        return
                    }
                    if (!event.accepted && event.key === Qt.Key_X && (event.modifiers & Qt.ControlModifier)) {
                        root._deleteWallpaperSelection()
                        event.accepted = true
                        return
                    }
                    if (!event.accepted && root._isLauncherTextEvent(event)) {
                        root._beginLauncherInput(event.text)
                        event.accepted = true
                    }
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Theme.background
            }
        }

        Item {
            anchors.top: parent.top
            anchors.topMargin: 14
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 14
            anchors.rightMargin: 14
            height: topSection.height + root._calendarTopGap + calendarFrame.height + root._wallpaperTopGap + wallpaperSection.height + root._wallpaperBottomGap

            Item {
                id: topSection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                height: columns.height
            }

            Item {
                id: columns
                anchors.left: topSection.left
                anchors.right: topSection.right
                anchors.top: topSection.top
                height: Math.max(leftColumn.height, rightColumn.height)

                Item {
                    id: leftColumn
                    anchors.left: parent.left
                    anchors.top: parent.top
                    width: root._columnWidth
                    height: rightColumn.height

                    TextMetrics {
                        id: weekdayMetrics
                        font.family: Theme.fontFamily
                        font.pixelSize: 12
                        font.letterSpacing: 1.6
                        text: "WEDNESDAY"
                    }

                    Item {
                        id: headerLauncherSection
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: 34

                        Item {
                            anchors.fill: parent

                            Item {
                                id: weekdayBox
                                anchors.centerIn: parent
                                width: Math.ceil(weekdayMetrics.advanceWidth) + 2
                                height: parent.height
                                opacity: root._searching ? 0.0 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                Text {
                                    id: weekdayTextItem
                                    anchors.centerIn: parent
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    text: root.weekdayText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 12
                                    font.letterSpacing: 1.6
                                    color: root._softText
                                }
                            }

                            Item {
                                id: dateBox
                                anchors.right: parent.right
                                anchors.verticalCenter: weekdayBox.verticalCenter
                                width: dateTextItem.implicitWidth
                                height: dateTextItem.implicitHeight
                                opacity: root._searching ? 0.0 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                Text {
                                    id: dateTextItem
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.dateText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: root._textColor
                                }
                            }

                            Item {
                                id: clockBox
                                anchors.left: parent.left
                                anchors.verticalCenter: weekdayBox.verticalCenter
                                width: timeMainTextItem.implicitWidth
                                height: timeMainTextItem.implicitHeight
                                opacity: root._searching ? 0.0 : 1.0
                                Behavior on opacity { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }

                                Text {
                                    id: timeMainTextItem
                                    anchors.left: parent.left
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: root.timeText
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 16
                                    font.bold: true
                                    color: root._textColor
                                }
                            }

                            Item {
                                anchors.left: searchIconSlot.right
                                anchors.leftMargin: 8
                                anchors.right: parent.right
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
                                        onTextChanged: {
                                            root._searchQuery = text
                                            root._filter(text)
                                        }
                                        Keys.onReturnPressed: root._launchTop()
                                        Keys.onEscapePressed: {
                                            if (text.length > 0) text = ""
                                            else root.hide()
                                        }
                                    }

                                    Text {
                                        visible: root._searching && root._ghostSuffix !== ""
                                        text: root._ghostSuffix
                                        font: searchInput.font
                                        color: Qt.rgba(root._textColor.r, root._textColor.g, root._textColor.b, 0.28)
                                    }
                                }
                            }

                            Item {
                                id: searchIconSlot
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: root._searching ? 22 : 0
                                height: 22
                                Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
                                clip: true

                                Image {
                                    id: searchIconImage
                                    anchors.centerIn: parent
                                    width: 22
                                    height: 22
                                    source: {
                                        if (!root._searching) return ""
                                        if (root._topResult) {
                                            const resolved = root._iconSource(root._topResult.icon || "")
                                            if (resolved) return resolved
                                        }
                                        return root._launcherFallbackIcon
                                    }
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                    mipmap: true
                                    smooth: true
                                    visible: root._searching && source !== "" && status === Image.Ready
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: root._launcherFallbackGlyph
                                    font.family: Theme.fontFamily
                                    font.pixelSize: 26
                                    color: root._softText
                                    visible: root._searching
                                        && !root._topResult
                                        && (!searchIconImage.source || searchIconImage.status !== Image.Ready)
                                }
                            }
                        }
                    }

                    Item {
                        id: mediaSection
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: headerLauncherSection.bottom
                        anchors.topMargin: 6
                        height: 140

                        ModuleSlot {
                            anchors.fill: parent
                            moduleType: "media"
                        }
                    }

                    Item {
                        id: quoteSection
                        anchors.left: parent.left
                        anchors.right: parent.right
                        height: quoteSlot.moduleItem ? quoteSlot.moduleItem.preferredHeight : 90
                        y: mediaSection.y + mediaSection.height + Math.max(0, (weatherSection.y - (mediaSection.y + mediaSection.height) - height) / 2) + 4

                        ModuleSlot {
                            id: quoteSlot
                            anchors.fill: parent
                            moduleType: "quote"
                        }
                    }

                    Item {
                        id: weatherSection
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: todaySection.top
                        anchors.bottomMargin: 6
                        height: 100

                        ModuleSlot {
                            anchors.fill: parent
                            moduleType: "weather"
                        }
                    }

                    Item {
                        id: todaySection
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: todaySlot.moduleItem ? todaySlot.moduleItem.preferredHeight : 120

                        ModuleSlot {
                            id: todaySlot
                            anchors.fill: parent
                            moduleType: "today"
                            extraProps: ({ showMonth: false })
                        }
                    }
                }

                Item {
                    id: rightColumn
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: root._rightColumnTopMargin
                    width: root._columnWidth
                    height: headerRow.height + root._sectionGap + garminSection.height

                    Item {
                        id: headerRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: Math.max(50, systemSlot.moduleItem ? systemSlot.moduleItem.preferredHeight : 50)
                        z: 1

                        Item {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: Math.round((parent.width - root._columnGap) * 0.85)

                            ModuleSlot {
                                id: notificationsSlot
                                anchors.fill: parent
                                moduleType: "notifications"
                            }
                        }

                        Item {
                            id: systemContainer
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.bottom: parent.bottom
                            width: parent.width - Math.round((parent.width - root._columnGap) * 0.85) - root._columnGap

                            ModuleSlot {
                                id: systemSlot
                                anchors.fill: parent
                                moduleType: "system"
                                extraProps: ({ compact: true })
                                hostControllerId: root.hostControllerId
                            }
                        }
                    }

                    Item {
                        id: garminSection
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: headerRow.bottom
                        anchors.topMargin: root._sectionGap
                        height: garminSlot.moduleItem ? garminSlot.moduleItem.preferredHeight : 300
                        z: 0

                        ModuleSlot {
                            id: garminSlot
                            anchors.fill: parent
                            moduleType: "garmin"
                        }
                    }
                }
            }

            Item {
                id: calendarFrame
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: topSection.bottom
                anchors.topMargin: root._calendarTopGap
                height: calendarSlot.moduleItem ? calendarSlot.moduleItem.preferredHeight : 420

                ModuleSlot {
                    id: calendarSlot
                    anchors.fill: parent
                    moduleType: "calendar"
                    extraProps: ({ showToday: false })
                }
            }

            Item {
                id: wallpaperSection
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: calendarFrame.bottom
                anchors.topMargin: root._wallpaperTopGap
                height: wallpaperSlot.moduleItem ? wallpaperSlot.moduleItem.preferredHeight : 120

                ModuleSlot {
                    id: wallpaperSlot
                    anchors.fill: parent
                    moduleType: "wallpaper"
                    eager: true
                }
            }

            ClippingRectangle {
                id: updateMenuOverlay
                visible: !!(systemSlot.moduleItem
                    && systemSlot.moduleItem.compactUpdateMenuVisible
                    && systemSlot.moduleItem.compactUpdateMenuText)
                x: rightColumn.x + headerRow.x + systemContainer.x + systemContainer.width - width
                y: rightColumn.y + headerRow.y + systemContainer.y + (systemSlot.moduleItem ? systemSlot.moduleItem.compactUpdateMenuTop : 0)
                width: systemSlot.moduleItem ? systemSlot.moduleItem.compactUpdateMenuWidth : 0
                height: systemSlot.moduleItem ? systemSlot.moduleItem.compactUpdateMenuHeight : 0
                radius: Theme.radiusSmall
                color: "transparent"
                z: 20
                onVisibleChanged: {
                    if (!visible && systemSlot.moduleItem)
                        systemSlot.moduleItem.compactUpdateMenuOverlayHovered = false
                }

                DesktopBackdrop {
                    anchors.fill: parent
                    screen: root.screen || Quickshell.screens[0]
                    sourceX: root._centerOffsetX + updateMenuOverlay.parent.x + updateMenuOverlay.x
                    sourceY: root._centerOffsetY + updateMenuOverlay.parent.y + updateMenuOverlay.y
                    mode: root._backdropMode
                    blur: root._backdropBlur
                    blurMax: root._backdropBlurMax
                    saturation: root._backdropSaturation
                    includeDesktopWidgets: false
                }

                Rectangle {
                    anchors.fill: parent
                    color: Theme.background
                }

                Text {
                    anchors.fill: parent
                    anchors.margins: 6
                    textFormat: Text.RichText
                    text: systemSlot.moduleItem
                        ? systemSlot.moduleItem._packages.map(systemSlot.moduleItem._formatUpdatePackageRich).join("<br>")
                        : ""
                    horizontalAlignment: Text.AlignRight
                    verticalAlignment: Text.AlignTop
                    font.family: Theme.fontFamily
                    font.pixelSize: 10
                    color: root._textColor
                }

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: {
                        if (systemSlot.moduleItem)
                            systemSlot.moduleItem.compactUpdateMenuOverlayHovered = true
                    }
                    onExited: {
                        if (systemSlot.moduleItem)
                            systemSlot.moduleItem.compactUpdateMenuOverlayHovered = false
                    }
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusLarge
            color: "transparent"
            border.width: Theme.borderWidth
            border.color: Theme.border
            visible: !Theme.borderIsRainbow || Theme.borderWidth <= 0
        }

        RainbowBorder {
            anchors.fill: parent
            visible: Theme.borderIsRainbow && Theme.borderWidth > 0
            radius: Theme.radiusLarge
            lineWidth: Theme.borderWidth
        }
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
