import QtQuick 2.15
import "../lib"

Item {
    id: root

    property var moduleConfig: null

    readonly property var _cfg: moduleConfig ? (moduleConfig.props || {}) : {}
    readonly property bool _nativePanel: _cfg.nativePanel === true
    readonly property string apiKey: _cfg.apiKey || ""
    readonly property string location: _cfg.location || "Berlin,DE"
    readonly property string units: _cfg.units || "metric"
    readonly property int refreshMins: _cfg.refreshInterval || 30

    readonly property color _textColor: Theme.color(moduleConfig, "textColor", Config.theme.text)
    readonly property color _accentColor: Theme.color(moduleConfig, "accentColor", Config.theme.accent)
    readonly property color _mutedText: Theme.textMuted
    readonly property color _subtleText: Theme.textMuted
    readonly property color _panelColor: Theme.surface
    readonly property color _raisedColor: Theme.accent
    readonly property color _borderColor: Theme.border
    readonly property color _frameColor: _panelColor
    readonly property color _lineColor: Theme.alpha(_borderColor, 0.7)
    readonly property color _glassColor: _raisedColor
    readonly property color _glassBorderColor: "transparent"
    readonly property color _iconBadgeColor: Theme.alpha(_accentColor, 0.16)
    readonly property string tempUnit: units === "metric" ? "°C" : "°F"
    readonly property bool _compact: width < 360
    readonly property real _columnWidth: width / 5
    readonly property int _contentOffsetX: 15
    readonly property string _EMPTY_ICON: "○"
    readonly property string _requestKey: WeatherState.requestKey(apiKey, location, units)
    readonly property var _weatherState: WeatherState.states[_requestKey] || ({
        cityText: location.toUpperCase(),
        conditionIconText: "○",
        tempText: "—" + tempUnit,
        rangeText: "H —°  L —°",
        intradayData: [],
        forecastData: [],
        showIntradayRow: false,
        showForecastRow: false,
        isEmptyState: true
    })
    readonly property string cityText: _weatherState.cityText || location.toUpperCase()
    readonly property string conditionIconText: _weatherState.conditionIconText || "○"
    readonly property string tempText: _weatherState.tempText || ("—" + tempUnit)
    readonly property string rangeText: _weatherState.rangeText || "H —°  L —°"
    readonly property var intradayData: _weatherState.intradayData || []
    readonly property var forecastData: _weatherState.forecastData || []
    readonly property bool _isEmptyState: _weatherState.isEmptyState !== false
    readonly property bool _showIntradayRow: _weatherState.showIntradayRow === true
    readonly property bool _showForecastRow: _weatherState.showForecastRow === true

    function _iconOffset(iconText, pixelSize) {
        return iconText === "🌥" ? Math.round(pixelSize * 0.16) : 0
    }

    Timer {
        interval: refreshMins * 60000
        repeat: true
        running: root.visible
        triggeredOnStart: true
        onTriggered: WeatherState.request(root.apiKey, root.location, root.units)
    }

    Item {
        anchors.fill: parent

        Rectangle {
            anchors.fill: parent
            radius: Theme.radiusLarge
            color: "transparent"
            border.color: "transparent"
            border.width: 0

            Column {
                visible: !root._isEmptyState
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.leftMargin: root._contentOffsetX
                anchors.topMargin: root._compact ? 10 : 12
                anchors.bottomMargin: root._compact ? 10 : 12
                spacing: 8

                Grid {
                    id: topRowGrid
                    width: parent.width
                    height: root._compact ? 32 : 34
                    columns: 5
                    columnSpacing: 0
                    rowSpacing: 0

                    Repeater {
                        model: 5

                        delegate: Item {
                            readonly property bool isCurrent: index === 0
                            readonly property var rowData: isCurrent ? {
                                label: "NOW",
                                icon: root.conditionIconText,
                                temp: root.tempText.replace(root.tempUnit.replace("°", ""), "")
                            } : (root.intradayData[index] || { label: "--", icon: "·", temp: "—" })

                            width: topRowGrid.width / 5
                            height: topRowGrid.height

                            Column {
                                anchors.fill: parent
                                spacing: 0

                                AccentText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 9
                                    text: rowData.label
                                    fontFamily: Theme.fontFamily
                                    fontPixelSize: 7
                                    fontLetterSpacing: 1
                                    color: isCurrent ? root._textColor : root._mutedText
                                    horizontalAlignment: Text.AlignHCenter
                                    radius: 5
                                    paddingX: 4
                                    paddingY: 0
                                    backgroundVisible: isCurrent
                                }

                                Item {
                                    width: parent.width
                                    height: parent.height - 9

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 4

                                        Item {
                                            width: root._compact ? 18 : 20
                                            height: parent.height

                                            Text {
                                                anchors.centerIn: parent
                                                anchors.verticalCenterOffset: root._iconOffset(rowData.icon, font.pixelSize)
                                                text: rowData.icon
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root._compact ? 22 : 23
                                                color: root._textColor
                                                horizontalAlignment: Text.AlignHCenter
                                                verticalAlignment: Text.AlignVCenter
                                            }
                                        }

                                        Column {
                                            width: root._compact ? 24 : 28
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 0

                                            Text {
                                                width: parent.width
                                                height: 8
                                                text: rowData.temp
                                                font.family: Theme.fontFamily
                                                font.pixelSize: 9
                                                font.bold: true
                                                color: root._textColor
                                                horizontalAlignment: Text.AlignHCenter
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Column {
                    width: parent.width
                    spacing: 0

                    Grid {
                        id: forecastGrid
                        visible: root._showForecastRow
                        width: parent.width
                        height: root._compact ? 32 : 34
                        columns: 5
                        columnSpacing: 0
                        rowSpacing: 0

                        Repeater {
                            model: 5

                            delegate: Item {
                                readonly property var rowData: root.forecastData[index] || {
                                    label: "---",
                                    icon: "·",
                                    high: "—",
                                    low: "—"
                                }

                                width: forecastGrid.width / 5
                                height: forecastGrid.height

                                Column {
                                    anchors.fill: parent
                                    spacing: 0

                                    Text {
                                        width: parent.width
                                        height: 9
                                        text: rowData.label
                                        font.family: Theme.fontFamily
                                        font.pixelSize: 7
                                        font.letterSpacing: 1
                                        color: root._mutedText
                                        horizontalAlignment: Text.AlignHCenter
                                    }

                                    Item {
                                        width: parent.width
                                        height: parent.height - 9

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 4

                                            Item {
                                                width: root._compact ? 18 : 20
                                                height: parent.height

                                            Text {
                                                anchors.centerIn: parent
                                                anchors.verticalCenterOffset: root._iconOffset(rowData.icon, font.pixelSize)
                                                text: rowData.icon
                                                font.family: Theme.fontFamily
                                                font.pixelSize: root._compact ? 22 : 23
                                                color: root._textColor
                                                    horizontalAlignment: Text.AlignHCenter
                                                    verticalAlignment: Text.AlignVCenter
                                                }
                                            }

                                            Column {
                                                width: root._compact ? 24 : 28
                                                anchors.verticalCenter: parent.verticalCenter
                                                spacing: 0

                                                Text {
                                                    width: parent.width
                                                    height: 9
                                                    text: rowData.high
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 9
                                                    font.bold: true
                                                    color: root._textColor
                                                    horizontalAlignment: Text.AlignHCenter
                                                }

                                                Text {
                                                    width: parent.width
                                                    height: 9
                                                    text: rowData.low
                                                    font.family: Theme.fontFamily
                                                    font.pixelSize: 8
                                                    color: root._mutedText
                                                    horizontalAlignment: Text.AlignHCenter
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Item {
                        visible: !root._showForecastRow
                        width: parent.width
                        height: root._compact ? 32 : 34

                        Text {
                            anchors.centerIn: parent
                            text: root._EMPTY_ICON
                            font.family: Theme.fontFamily
                            font.pixelSize: root._compact ? 26 : 28
                            color: root._mutedText
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }

            Item {
                visible: root._isEmptyState
                anchors.fill: parent

                Text {
                    anchors.centerIn: parent
                    text: root._EMPTY_ICON
                    font.family: Theme.fontFamily
                    font.pixelSize: root._compact ? 34 : 40
                    color: root._mutedText
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
            }
        }
    }
}
