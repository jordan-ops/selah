// Ported from Nebula's Widgets/CalendarMiniWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

WidgetHost {
    id: root
    configKey: "calendarMini"
    defaultPos: Qt.point(420, 300)
    tile: WidgetSizes.small

    readonly property int startDay: (SettingsConfig.widgets.calendarMiniMonday ?? true) ? 1 : 0
    readonly property bool dimOther: SettingsConfig.widgets.calendarMiniDimOther ?? true

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

    optionsComponent: Component {
        ColumnLayout {
            spacing: 3

            Repeater {
                model: [{ key: "calendarMiniMonday", label: "Start on Monday", sub: "Off starts the week on Sunday", def: true },
                        { key: "calendarMiniDimOther", label: "Dim other months", sub: "Leading and trailing days", def: true }]

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
            spacing: 6

            CustomText {
                Layout.fillWidth: true
                content: ServiceClock.month.substring(0, 3).toUpperCase() + " " + ServiceClock.year
                size: 12
                weight: 700
                customColor: Colors.outline
                font.letterSpacing: 0.6
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: 1
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
                            size: 9
                            weight: 700
                            customColor: Colors.outline
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

                        readonly property bool today: cell.modelData.isToday
                        readonly property real side: Math.min(cell.width, cell.height)

                        Rectangle {
                            anchors.centerIn: parent
                            width: cell.side
                            height: cell.side
                            radius: cell.side / 2
                            visible: cell.today
                            color: Colors.primary
                        }

                        CustomText {
                            anchors.centerIn: parent
                            content: cell.modelData.day
                            size: 10
                            weight: cell.today ? 700 : 500
                            customColor: cell.today ? Colors.primaryText
                                : !cell.modelData.isCurrentMonth ? (root.dimOther ? Colors.outlineVariant : "transparent")
                                : cell.modelData.isHoliday ? Colors.tertiary
                                : Colors.surfaceText
                        }

                        CustomToolTip {
                            visible: cellHover.containsMouse && cell.modelData.isHoliday
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
