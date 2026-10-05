// Ported from Nebula's Widgets/CalendarStampWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "calendarMath.js" as CalMath

WidgetHost {
    id: root
    configKey: "calendarStamp"
    defaultPos: Qt.point(1100, 440)
    tile: WidgetSizes.tall

    readonly property string _serif: SettingsConfig.general.displayFont
    readonly property bool showPostmark: SettingsConfig.widgets.calendarStampPostmark ?? true

    readonly property var now: {
        ServiceClock.date
        return new Date()
    }
    readonly property int week: CalMath.isoWeek(root.now)
    readonly property var nextHoliday: {
        const up = CalMath.upcomingHolidays(ServiceClock.holidayData, root.now, 1)
        return up.length > 0 ? up[0] : null
    }
    readonly property string place: ServiceWeather.locationData ? ServiceWeather.cityName.toUpperCase() : "POSTED"
    readonly property string ringText: root.place + " · " + root.now.getFullYear() + " · "

    function stampPath(w, h, r, pitch) {
        const nx = Math.max(1, Math.floor((w - 4 * r) / pitch) + 1)
        const ny = Math.max(1, Math.floor((h - 4 * r) / pitch) + 1)
        const ox = (w - (nx - 1) * pitch) / 2
        const oy = (h - (ny - 1) * pitch) / 2
        const arc = (x, y) => " A " + r + " " + r + " 0 0 0 " + x.toFixed(1) + " " + y.toFixed(1)
        let p = "M 0 0"
        for (let i = 0; i < nx; i++) {
            const cx = ox + i * pitch
            p += " L " + (cx - r).toFixed(1) + " 0" + arc(cx + r, 0)
        }
        p += " L " + w + " 0"
        for (let j = 0; j < ny; j++) {
            const cy = oy + j * pitch
            p += " L " + w + " " + (cy - r).toFixed(1) + arc(w, cy + r)
        }
        p += " L " + w + " " + h
        for (let i = nx - 1; i >= 0; i--) {
            const cx = ox + i * pitch
            p += " L " + (cx + r).toFixed(1) + " " + h + arc(cx - r, h)
        }
        p += " L 0 " + h
        for (let j = ny - 1; j >= 0; j--) {
            const cy = oy + j * pitch
            p += " L 0 " + (cy + r).toFixed(1) + arc(0, cy - r)
        }
        return p + " Z"
    }

    optionsComponent: Component {
        CalendarOptionList {
            model: [{ key: "calendarStampPostmark", label: "Show postmark", sub: "Your city and the year stamped over the corner", def: true }]
        }
    }

    WidgetCard {
        anchors.fill: parent

        Item {
            id: stamp
            x: 18
            y: 18
            width: Math.min(124, parent.width - 60)
            height: Math.round(stamp.width * 1.27)
            rotation: -2

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: "transparent"
                    fillColor: Colors.primary
                    PathSvg { path: root.stampPath(stamp.width, stamp.height, 4, 12) }
                }
            }

            Rectangle {
                anchors.fill: parent
                anchors.margins: 11
                color: "transparent"
                border.width: 1
                border.color: Qt.alpha(Colors.primaryText, 0.3)

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0

                    CustomText {
                        Layout.alignment: Qt.AlignHCenter
                        content: ServiceClock.month.toUpperCase()
                        size: 9
                        weight: 700
                        customColor: Colors.primaryText
                        font.letterSpacing: 2
                    }
                    CustomText {
                        Layout.alignment: Qt.AlignHCenter
                        content: String(parseInt(ServiceClock.date))
                        size: 64
                        weight: 700
                        family: root._serif
                        renderType: Text.QtRendering
                        customColor: Colors.primaryText
                        lineHeightMode: Text.FixedHeight
                        lineHeight: 64
                    }
                    CustomText {
                        Layout.alignment: Qt.AlignHCenter
                        content: ServiceClock.day
                        size: 14
                        weight: 400
                        family: root._serif
                        font.italic: true
                        renderType: Text.QtRendering
                        customColor: Colors.primaryText
                    }
                    CustomText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 6
                        content: "WEEK " + root.week + " · " + ServiceClock.year
                        size: 8
                        weight: 600
                        customColor: Qt.alpha(Colors.primaryText, 0.7)
                        font.letterSpacing: 1.2
                    }
                }
            }
        }

        Shape {
            visible: root.showPostmark
            x: 42
            y: stamp.y + stamp.height - 20
            width: 120
            height: 40
            rotation: -12
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeColor: Qt.alpha(Colors.tertiary, 0.7)
                strokeWidth: 1.6
                fillColor: "transparent"
                PathSvg {
                    path: "M0 8c10-6 20 6 30 0s20 6 30 0 20 6 30 0 20 6 30 0"
                        + "M0 20c10-6 20 6 30 0s20 6 30 0 20 6 30 0 20 6 30 0"
                        + "M0 32c10-6 20 6 30 0s20 6 30 0 20 6 30 0 20 6 30 0"
                }
            }
        }

        Item {
            id: postmark
            visible: root.showPostmark
            width: 92
            height: 92
            x: parent.width - width - 4
            y: stamp.y + stamp.height - 48
            rotation: -12

            Rectangle {
                anchors.centerIn: parent
                width: 84
                height: 84
                radius: 42
                color: "transparent"
                border.width: 2
                border.color: Qt.alpha(Colors.tertiary, 0.85)
            }
            Rectangle {
                anchors.centerIn: parent
                width: 48
                height: 48
                radius: 24
                color: "transparent"
                border.width: 1.5
                border.color: Qt.alpha(Colors.tertiary, 0.85)
            }

            Repeater {
                model: root.ringText.length

                Item {
                    required property int index
                    x: postmark.width / 2
                    y: postmark.height / 2
                    rotation: 360 * index / root.ringText.length

                    CustomText {
                        x: -width / 2
                        y: -33 - height / 2
                        content: root.ringText[parent.index]
                        size: 8
                        weight: 700
                        customColor: Colors.tertiary
                    }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                spacing: -2
                CustomText {
                    Layout.alignment: Qt.AlignHCenter
                    content: ServiceClock.month.substring(0, 3).toUpperCase()
                    size: 10
                    weight: 700
                    customColor: Colors.tertiary
                }
                CustomText {
                    Layout.alignment: Qt.AlignHCenter
                    content: String(parseInt(ServiceClock.date))
                    size: 10
                    weight: 700
                    customColor: Colors.tertiary
                }
            }
        }

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.margins: 18
            anchors.bottomMargin: 16
            spacing: 3

            Rectangle {
                Layout.fillWidth: true
                Layout.bottomMargin: 7
                implicitHeight: 1
                color: Qt.alpha(Colors.surfaceText, 0.14)
            }
            CustomText {
                content: "NEXT HOLIDAY"
                size: 10
                weight: 600
                customColor: Colors.outline
                font.letterSpacing: 1.4
            }
            CustomText {
                Layout.fillWidth: true
                content: root.nextHoliday ? root.nextHoliday.name : "None left this year"
                wrapMode: Text.WordWrap
                elide: Text.ElideNone
                maximumLineCount: 2
                lineHeight: 0.95
                size: 17
                weight: 600
                family: root._serif
                renderType: Text.QtRendering
            }
            CustomText {
                Layout.fillWidth: true
                visible: root.nextHoliday !== null
                textFormat: Text.StyledText
                content: root.nextHoliday
                    ? Qt.formatDate(root.nextHoliday.date, "ddd d MMM") + " · <font color=\"" + Colors.tertiary + "\"><b>"
                      + (root.nextHoliday.days === 1 ? "tomorrow" : "in " + root.nextHoliday.days + " days") + "</b></font>"
                    : ""
                size: 12
                weight: 400
                customColor: Colors.surfaceVariantText
            }
        }
    }
}
