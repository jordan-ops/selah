// Ported from Nebula's Widgets/CalendarDaylightWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "calendarMath.js" as CalMath

WidgetHost {
    id: root
    configKey: "calendarDaylight"
    defaultPos: Qt.point(420, 100)
    tile: WidgetSizes.strip

    readonly property string _serif: "Noto Serif Display"
    readonly property bool showPlace: SettingsConfig.widgets.calendarDaylightPlace ?? true

    readonly property var astro: root.preview && !ServiceWeather.astronomy
        ? ({ sunrise: "06:16 AM", sunset: "06:23 PM" }) : ServiceWeather.astronomy
    readonly property int sunriseMin: CalMath.parseClock(root.astro ? root.astro.sunrise : "")
    readonly property int sunsetMin: CalMath.parseClock(root.astro ? root.astro.sunset : "")
    readonly property bool hasData: root.sunriseMin >= 0 && root.sunsetMin > root.sunriseMin

    readonly property int nowMin: {
        ServiceClock.minute
        const d = new Date()
        return d.getHours() * 60 + d.getMinutes()
    }
    readonly property bool isDay: root.hasData && root.nowMin >= root.sunriseMin && root.nowMin < root.sunsetMin
    readonly property real progress: !root.hasData ? 0
        : Math.max(0, Math.min(1, (root.nowMin - root.sunriseMin) / (root.sunsetMin - root.sunriseMin)))

    readonly property string footer: {
        if (!root.hasData) return "Waiting for sunrise times"
        const light = CalMath.fmtDuration(root.sunsetMin - root.sunriseMin) + " of light"
        if (root.nowMin < root.sunriseMin) return light + " · sunrise in " + CalMath.fmtDuration(root.sunriseMin - root.nowMin)
        if (root.nowMin >= root.sunsetMin) return light + " · sunrise in " + CalMath.fmtDuration(root.sunriseMin + 1440 - root.nowMin)
        return light + " · " + CalMath.fmtDuration(root.sunsetMin - root.nowMin) + " left"
    }

    optionsComponent: Component {
        CalendarOptionList {
            model: [{ key: "calendarDaylightPlace", label: "Show place", sub: "City and temperature under the date", def: true }]
        }
    }

    WidgetCard {
        anchors.fill: parent

        RowLayout {
            anchors.fill: parent
            anchors.margins: parent.pad
            anchors.leftMargin: parent.pad
            anchors.rightMargin: parent.pad
            spacing: 16

            ColumnLayout {
                Layout.preferredWidth: 74
                Layout.alignment: Qt.AlignVCenter
                spacing: 2

                CustomText {
                    content: String(parseInt(ServiceClock.date))
                    size: 52
                    weight: 700
                    family: root._serif
                    renderType: Text.QtRendering
                    lineHeightMode: Text.FixedHeight
                    lineHeight: 50
                }
                CustomText {
                    Layout.topMargin: 4
                    content: ServiceClock.day.substring(0, 3) + " · " + ServiceClock.month.substring(0, 3)
                    size: 12
                    weight: 500
                    customColor: Colors.surfaceVariantText
                }
                CustomText {
                    visible: root.showPlace && ServiceWeather.currentCondition !== null
                    Layout.maximumWidth: 90
                    content: ServiceWeather.cityName + ", " + ServiceWeather.temperature
                    size: 11
                    weight: 400
                    customColor: Colors.outline
                }
            }

            ColumnLayout {
                id: side
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                Item {
                    id: sky
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    readonly property real barY: sky.height - 8
                    readonly property real baseY: sky.barY - 4
                    readonly property real srX: root.hasData ? sky.width * root.sunriseMin / 1440 : sky.width * 0.25
                    readonly property real ssX: root.hasData ? sky.width * root.sunsetMin / 1440 : sky.width * 0.75
                    readonly property real nowX: sky.width * root.nowMin / 1440
                    readonly property real rx: (sky.ssX - sky.srX) / 2
                    readonly property real ry: Math.max(10, Math.min(sky.baseY - 10, sky.rx * 0.62))
                    readonly property real cx: (sky.srX + sky.ssX) / 2
                    readonly property real sunA: Math.PI * (1 - root.progress)
                    readonly property real sunX: sky.cx + sky.rx * Math.cos(sky.sunA)
                    readonly property real sunY: sky.baseY - sky.ry * Math.sin(sky.sunA)

                    Shape {
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer

                        ShapePath {
                            strokeColor: Qt.alpha(Colors.surfaceText, 0.18)
                            strokeWidth: 1.5
                            strokeStyle: ShapePath.DashLine
                            dashPattern: [2, 3]
                            fillColor: "transparent"
                            startX: sky.srX
                            startY: sky.baseY
                            PathArc {
                                x: sky.ssX
                                y: sky.baseY
                                radiusX: sky.rx
                                radiusY: sky.ry
                            }
                        }

                        ShapePath {
                            strokeColor: root.isDay ? Colors.tertiary : "transparent"
                            strokeWidth: 2.5
                            capStyle: ShapePath.RoundCap
                            fillColor: "transparent"
                            startX: sky.srX
                            startY: sky.baseY
                            PathArc {
                                x: sky.sunX
                                y: sky.sunY
                                radiusX: sky.rx
                                radiusY: sky.ry
                            }
                        }
                    }

                    Rectangle {
                        visible: root.isDay
                        x: sky.sunX - width / 2
                        y: sky.sunY - height / 2
                        width: 22
                        height: 22
                        radius: 11
                        color: Qt.alpha(Colors.tertiary, 0.22)
                    }

                    Rectangle {
                        x: (root.isDay ? sky.sunX : sky.nowX) - width / 2
                        y: (root.isDay ? sky.sunY : sky.barY + 4) - height / 2
                        width: root.isDay ? 12 : 8
                        height: width
                        radius: width / 2
                        color: root.isDay ? Colors.tertiary : Colors.surfaceText
                        border.width: root.isDay ? 0 : 2
                        border.color: WidgetSizes.cardColor
                    }

                    Rectangle {
                        y: sky.barY
                        width: sky.width
                        height: 8
                        radius: 4
                        color: Colors.surfaceContainerHighest
                        z: -1

                        Rectangle {
                            x: sky.srX
                            width: sky.ssX - sky.srX
                            height: 8
                            radius: 4
                            color: Colors.primaryContainer
                        }

                        Rectangle {
                            x: sky.srX
                            width: Math.max(0, Math.min(sky.nowX, sky.ssX) - sky.srX)
                            visible: root.nowMin > root.sunriseMin
                            height: 8
                            radius: 4
                            color: Colors.primary
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    CustomText {
                        content: root.hasData ? "↑ " + CalMath.fmtClock(root.sunriseMin) : "↑ —"
                        size: 11
                        weight: 500
                        customColor: Colors.surfaceVariantText
                    }
                    Item { Layout.fillWidth: true }
                    CustomText {
                        content: root.hasData ? "↓ " + CalMath.fmtClock(root.sunsetMin) : "↓ —"
                        size: 11
                        weight: 500
                        customColor: Colors.surfaceVariantText
                    }
                }

                CustomText {
                    Layout.fillWidth: true
                    content: root.footer
                    size: 11
                    weight: 400
                    customColor: Colors.outline
                }
            }
        }
    }
}
