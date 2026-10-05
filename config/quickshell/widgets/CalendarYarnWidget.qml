// Ported from Nebula's Widgets/CalendarYarnWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

WidgetHost {
    id: root
    configKey: "calendarYarn"
    defaultPos: Qt.point(660, 300)
    tile: WidgetSizes.small

    readonly property string _serif: "Noto Serif Display"

    readonly property int startDay: (SettingsConfig.widgets.calendarYarnMonday ?? true) ? 1 : 0
    readonly property bool showFooter: SettingsConfig.widgets.calendarYarnFooter ?? true

    readonly property var cells: {
        ServiceClock.date
        const now = new Date()
        return ServiceClock.generateCalendarGrid(now.getFullYear(), now.getMonth(), root.startDay)
    }

    readonly property int today: parseInt(ServiceClock.date)

    readonly property int daysLeft: {
        ServiceClock.date
        const now = new Date()
        return ServiceClock.getDaysInMonth(now.getFullYear(), now.getMonth()) - now.getDate()
    }

    readonly property string todayInfo: {
        for (let i = 0; i < root.cells.length; i++)
            if (root.cells[i].isToday && root.cells[i].isHoliday)
                return root.cells[i].info ?? ""
        return ""
    }

    optionsComponent: Component {
        ColumnLayout {
            spacing: 3

            Repeater {
                model: [{ key: "calendarYarnMonday", label: "Start on Monday", sub: "Off starts the week on Sunday", def: true },
                        { key: "calendarYarnFooter", label: "Show footer", sub: "Holiday name, or days left in the month", def: true }]

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

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: parent.pad
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 9

                CustomText {
                    content: String(root.today)
                    size: 40
                    weight: 700
                    customColor: Colors.primary
                    family: root._serif
                    renderType: Text.QtRendering
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: -2

                    CustomText {
                        content: ServiceClock.day
                        size: 12
                        weight: 700
                    }

                    CustomText {
                        content: ServiceClock.month.substring(0, 3).toUpperCase() + " " + ServiceClock.year
                        size: 10
                        weight: 600
                        customColor: Colors.outline
                        font.letterSpacing: 1.2
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: 2
                columnSpacing: 2

                Repeater {
                    model: root.cells

                    delegate: Item {
                        id: cell
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        readonly property bool inMonth: cell.modelData.isCurrentMonth
                        readonly property bool isToday: cell.modelData.isToday
                        readonly property bool holiday: cell.inMonth && cell.modelData.isHoliday
                        readonly property bool knitted: cell.inMonth && !cell.isToday && cell.modelData.day < root.today
                        readonly property real side: Math.min(cell.width, cell.height)

                        Rectangle {
                            anchors.centerIn: parent
                            visible: cell.isToday
                            width: Math.min(19, cell.side)
                            height: width
                            radius: width / 2
                            color: Qt.alpha(Colors.primary, 0.22)
                        }

                        Rectangle {
                            anchors.centerIn: parent
                            visible: cell.inMonth
                            width: cell.isToday ? 10 : 7
                            height: width
                            radius: width / 2
                            color: cell.isToday ? Colors.primary
                                : cell.holiday ? Colors.tertiary
                                : cell.knitted ? Colors.outline
                                : "transparent"
                            border.width: cell.isToday || cell.holiday || cell.knitted ? 0 : 1
                            border.color: Colors.outlineVariant
                        }

                        CustomToolTip {
                            visible: cellHover.containsMouse && cell.holiday
                                && (cell.modelData.info ?? "") !== ""
                            content: (cell.modelData.info ?? "") + " · " + cell.modelData.day
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

            ColumnLayout {
                Layout.fillWidth: true
                visible: root.showFooter
                spacing: 6

                Shape {
                    id: stitch
                    Layout.fillWidth: true
                    implicitHeight: 1
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        strokeColor: Colors.outlineVariant
                        strokeWidth: 1
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [2, 3]
                        fillColor: "transparent"
                        startX: 0
                        startY: 0.5

                        PathLine { x: stitch.width; y: 0.5 }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        implicitWidth: 5
                        implicitHeight: 5
                        radius: 3
                        color: root.todayInfo !== "" ? Colors.tertiary : Colors.primary
                    }

                    CustomText {
                        Layout.fillWidth: true
                        content: root.todayInfo !== "" ? root.todayInfo
                            : root.daysLeft === 0 ? "Last day of the month"
                            : root.daysLeft + " days left"
                        size: 10
                        weight: 600
                        customColor: Colors.outline
                    }
                }
            }
        }
    }
}
