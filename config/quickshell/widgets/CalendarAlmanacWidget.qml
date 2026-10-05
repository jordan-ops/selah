// Ported from Nebula's Widgets/CalendarAlmanacWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

WidgetHost {
    id: root
    configKey: "calendarAlmanac"
    defaultPos: Qt.point(880, 300)
    tile: WidgetSizes.wide

    readonly property string _serif: "Noto Serif Display"

    readonly property int startDay: (SettingsConfig.widgets.calendarAlmanacMonday ?? true) ? 1 : 0
    readonly property bool dimOther: SettingsConfig.widgets.calendarAlmanacDimOther ?? true

    readonly property var cells: {
        ServiceClock.date
        const now = new Date()
        return ServiceClock.generateCalendarGrid(now.getFullYear(), now.getMonth(), root.startDay)
    }

    readonly property var weekLetters: {
        const base = ["S", "M", "T", "W", "T", "F", "S"]
        const out = []
        for (let i = 0; i < 7; i++)
            out.push(base[(i + root.startDay) % 7])
        return out
    }

    readonly property string todayInfo: {
        for (let i = 0; i < root.cells.length; i++)
            if (root.cells[i].isToday && root.cells[i].isHoliday)
                return root.cells[i].info ?? ""
        return ""
    }

    readonly property int weekNumber: {
        ServiceClock.date
        const now = new Date()
        const t = new Date(now.getFullYear(), now.getMonth(), now.getDate())
        t.setDate(t.getDate() - ((t.getDay() + 6) % 7) + 3)
        const first = new Date(t.getFullYear(), 0, 4)
        first.setDate(first.getDate() - ((first.getDay() + 6) % 7) + 3)
        return 1 + Math.round((t.getTime() - first.getTime()) / 604800000)
    }

    optionsComponent: Component {
        ColumnLayout {
            spacing: 3

            Repeater {
                model: [{ key: "calendarAlmanacMonday", label: "Start on Monday", sub: "Off starts the week on Sunday", def: true },
                        { key: "calendarAlmanacDimOther", label: "Dim other months", sub: "Leading and trailing days", def: true }]

                delegate: CustomCard {
                    id: optRow
                    required property var modelData
                    required property int index

                    autoRadius: false
                    topRadius: optRow.index === 0 ? 18 : 5
                    bottomRadius: optRow.index === 1 ? 18 : 5

                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            CustomText { content: optRow.modelData.label; size: 13 }
                            CustomText {
                                Layout.fillWidth: true
                                content: optRow.modelData.sub
                                size: 11
                                customColor: Colors.outline
                                wrapMode: Text.Wrap
                                elide: Text.ElideNone
                            }
                        }

                        CustomToogle {
                            isToggleOn: SettingsConfig.widgets[optRow.modelData.key] ?? optRow.modelData.def
                            onToggled: state => {
                                const o = {}
                                o[optRow.modelData.key] = state
                                SettingsConfig.widgets = Object.assign({}, SettingsConfig.widgets, o)
                            }
                        }
                    }
                }
            }
        }
    }

    WidgetCard {
        anchors.fill: parent

        Shape {
            anchors.fill: parent
            anchors.margins: 9
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                strokeColor: Qt.alpha(Colors.outline, 0.75)
                strokeWidth: 1
                strokeStyle: ShapePath.DashLine
                dashPattern: [2, 2.6]
                fillColor: "transparent"

                PathRectangle {
                    x: 0.5
                    y: 0.5
                    width: Math.max(0, root.width - 19)
                    height: Math.max(0, root.height - 19)
                    radius: WidgetSizes.radius - 10
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 22
            spacing: 13

            ColumnLayout {
                Layout.preferredWidth: 100
                Layout.fillHeight: true
                spacing: 0

                CustomText {
                    content: ServiceClock.month
                    size: 13
                    weight: 600
                    customColor: Colors.outline
                    family: root._serif
                    renderType: Text.QtRendering
                }

                CustomText {
                    Layout.topMargin: -4
                    content: String(parseInt(ServiceClock.date))
                    size: 54
                    weight: 700
                    family: root._serif
                    renderType: Text.QtRendering
                }

                CustomText {
                    Layout.topMargin: -4
                    content: ServiceClock.day.toUpperCase()
                    size: 10
                    weight: 700
                    customColor: Colors.outline
                    font.letterSpacing: 1.8
                }

                Item { Layout.fillHeight: true }

                Rectangle {
                    Layout.preferredWidth: Math.min(chipText.implicitWidth + 18, 100)
                    Layout.preferredHeight: 21
                    radius: 11
                    color: root.todayInfo !== "" ? Qt.alpha(Colors.tertiary, 0.16)
                                                 : Qt.alpha(Colors.primary, 0.14)

                    CustomText {
                        id: chipText
                        anchors.centerIn: parent
                        width: parent.width - 16
                        content: root.todayInfo !== "" ? root.todayInfo : "WEEK " + root.weekNumber
                        size: 10
                        weight: 700
                        customColor: root.todayInfo !== "" ? Colors.tertiary : Colors.primary
                        font.letterSpacing: 0.8
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            Shape {
                id: seam
                Layout.fillHeight: true
                Layout.preferredWidth: 1
                preferredRendererType: Shape.CurveRenderer

                ShapePath {
                    strokeColor: Qt.alpha(Colors.outline, 0.45)
                    strokeWidth: 1
                    strokeStyle: ShapePath.DashLine
                    dashPattern: [2, 3]
                    fillColor: "transparent"
                    startX: 0.5
                    startY: 0

                    PathLine { x: 0.5; y: seam.height }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: 0
                columnSpacing: 1

                Repeater {
                    model: root.weekLetters

                    delegate: Item {
                        required property string modelData
                        Layout.fillWidth: true
                        Layout.preferredHeight: 13

                        CustomText {
                            anchors.centerIn: parent
                            content: parent.modelData
                            size: 8
                            weight: 700
                            customColor: Colors.outline
                            font.letterSpacing: 0.5
                        }
                    }
                }

                Repeater {
                    model: root.cells

                    delegate: Item {
                        id: cell
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        readonly property bool isToday: cell.modelData.isToday
                        readonly property bool holiday: cell.modelData.isHoliday
                        readonly property real side: Math.min(cell.width, cell.height)

                        Rectangle {
                            anchors.centerIn: parent
                            visible: cell.isToday
                            width: Math.min(cell.side, 19)
                            height: width
                            radius: width / 2
                            color: Colors.primary
                        }

                        CustomText {
                            id: dayText
                            anchors.centerIn: parent
                            content: cell.modelData.day
                            size: 10
                            weight: cell.isToday ? 700 : 500
                            customColor: cell.isToday ? Colors.primaryText
                                : !cell.modelData.isCurrentMonth ? (root.dimOther ? Colors.outlineVariant : "transparent")
                                : cell.holiday ? Colors.tertiary
                                : Colors.surfaceText
                        }

                        Rectangle {
                            visible: cell.holiday && cell.modelData.isCurrentMonth && !cell.isToday
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.top: dayText.bottom
                            anchors.topMargin: 0
                            width: 10
                            height: 1
                            color: Qt.alpha(Colors.tertiary, 0.7)
                        }

                        CustomToolTip {
                            visible: cellHover.containsMouse && cell.holiday
                                && (cell.modelData.info ?? "") !== ""
                            content: cell.modelData.info ?? ""
                        }

                        MouseArea {
                            id: cellHover
                            anchors.fill: parent
                            hoverEnabled: true
                            acceptedButtons: Qt.NoButton
                        }
                    }
                }
            }
        }
    }
}
