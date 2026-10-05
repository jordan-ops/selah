// Ported from Nebula's Widgets/CalendarYearWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "calendarMath.js" as CalMath

WidgetHost {
    id: root
    configKey: "calendarYear"
    defaultPos: Qt.point(760, 440)
    tile: WidgetSizes.large

    readonly property string _serif: SettingsConfig.general.displayFont
    readonly property bool showHolidays: SettingsConfig.widgets.calendarYearHolidays ?? true

    readonly property var now: {
        ServiceClock.date
        return new Date()
    }
    readonly property int year: root.now.getFullYear()
    readonly property int yearDays: CalMath.daysInYear(root.year)
    readonly property int dayNum: CalMath.dayOfYear(root.now)

    readonly property var months: {
        const out = []
        let acc = 0
        for (let m = 0; m < 12; m++) {
            const n = new Date(root.year, m + 1, 0).getDate()
            out.push({ m: m, start: acc, days: n, letter: "JFMAMJJASOND"[m] })
            acc += n
        }
        return out
    }

    readonly property var upcoming: CalMath.upcomingHolidays(ServiceClock.holidayData, root.now, 8)

    readonly property var nextHoliday: root.upcoming.length > 0 ? root.upcoming[0] : null

    function angleOf(dayIndex) {
        return -90 + 360 * dayIndex / root.yearDays
    }

    optionsComponent: Component {
        CalendarOptionList {
            model: [{ key: "calendarYearHolidays", label: "Show holidays", sub: "Dots on the ring and the next one by name", def: true }]
        }
    }

    WidgetCard {
        anchors.fill: parent

        Item {
            id: wheel
            anchors.fill: parent

            readonly property real cx: wheel.width / 2
            readonly property real cy: wheel.height / 2
            readonly property real r: Math.min(wheel.width, wheel.height) / 2 - 39
            readonly property real gap: 2.6

            Repeater {
                model: root.months

                Shape {
                    id: seg
                    required property var modelData
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    readonly property real a0: root.angleOf(seg.modelData.start) + wheel.gap / 2
                    readonly property real sweep: 360 * seg.modelData.days / root.yearDays - wheel.gap
                    readonly property bool done: seg.modelData.m < root.now.getMonth()
                    readonly property bool current: seg.modelData.m === root.now.getMonth()

                    ShapePath {
                        strokeColor: seg.done ? Qt.alpha(Colors.primary, 0.55) : Colors.surfaceContainerHighest
                        strokeWidth: 12
                        capStyle: ShapePath.FlatCap
                        fillColor: "transparent"
                        PathAngleArc {
                            centerX: wheel.cx
                            centerY: wheel.cy
                            radiusX: wheel.r
                            radiusY: wheel.r
                            startAngle: seg.a0
                            sweepAngle: seg.sweep
                        }
                    }

                    ShapePath {
                        strokeColor: seg.current ? Colors.primary : "transparent"
                        strokeWidth: 12
                        capStyle: ShapePath.FlatCap
                        fillColor: "transparent"
                        PathAngleArc {
                            centerX: wheel.cx
                            centerY: wheel.cy
                            radiusX: wheel.r
                            radiusY: wheel.r
                            startAngle: seg.a0
                            sweepAngle: Math.max(0.1, Math.min(seg.sweep, 360 * root.now.getDate() / root.yearDays - wheel.gap / 2))
                        }
                    }
                }
            }

            Repeater {
                model: root.months

                CustomText {
                    required property var modelData
                    readonly property real a: (root.angleOf(modelData.start + modelData.days / 2)) * Math.PI / 180
                    readonly property bool current: modelData.m === root.now.getMonth()
                    x: wheel.cx + (wheel.r - 22) * Math.cos(a) - width / 2
                    y: wheel.cy + (wheel.r - 22) * Math.sin(a) - height / 2
                    content: modelData.letter
                    size: 9
                    weight: current ? 700 : 500
                    customColor: current ? Colors.primary : Colors.outline
                }
            }

            Repeater {
                model: root.showHolidays ? root.upcoming : []

                Rectangle {
                    required property var modelData
                    readonly property real a: root.angleOf(CalMath.dayOfYear(modelData.date) - 0.5) * Math.PI / 180
                    x: wheel.cx + wheel.r * Math.cos(a) - width / 2
                    y: wheel.cy + wheel.r * Math.sin(a) - height / 2
                    width: 7
                    height: 7
                    radius: 3.5
                    color: Colors.tertiary
                }
            }

            Item {
                readonly property real a: root.angleOf(root.dayNum - 0.5) * Math.PI / 180
                x: wheel.cx + wheel.r * Math.cos(a)
                y: wheel.cy + wheel.r * Math.sin(a)

                Rectangle {
                    anchors.centerIn: parent
                    width: 22
                    height: 22
                    radius: 11
                    color: Qt.alpha(Colors.tertiary, 0.25)
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 13
                    height: 13
                    radius: 6.5
                    color: Colors.tertiary
                    border.width: 2
                    border.color: Colors.surface
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: 0

                CustomText {
                    Layout.alignment: Qt.AlignHCenter
                    content: "DAY"
                    size: 10
                    weight: 600
                    customColor: Colors.outline
                    font.letterSpacing: 1.6
                }
                CustomText {
                    Layout.alignment: Qt.AlignHCenter
                    content: String(root.dayNum)
                    size: 56
                    weight: 700
                    family: root._serif
                    renderType: Text.QtRendering
                    lineHeightMode: Text.FixedHeight
                    lineHeight: 58
                }
                CustomText {
                    Layout.alignment: Qt.AlignHCenter
                    content: "of " + root.year + " · " + (root.yearDays - root.dayNum) + " to go"
                    size: 12
                    weight: 400
                    customColor: Colors.surfaceVariantText
                }
                CustomText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    Layout.maximumWidth: wheel.r * 1.4
                    visible: root.showHolidays && root.nextHoliday !== null
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    elide: Text.ElideNone
                    maximumLineCount: 2
                    content: root.nextHoliday ? root.nextHoliday.name : ""
                    size: 11
                    weight: 500
                    customColor: Colors.tertiary
                }
                CustomText {
                    Layout.alignment: Qt.AlignHCenter
                    visible: root.showHolidays && root.nextHoliday !== null
                    content: root.nextHoliday ? (root.nextHoliday.days === 1 ? "tomorrow" : "in " + root.nextHoliday.days + " days") : ""
                    size: 10
                    weight: 400
                    customColor: Colors.outline
                }
            }
        }
    }
}
