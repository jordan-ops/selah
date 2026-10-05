// Ported from Nebula's Widgets/CalendarWindowsWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "calendarMath.js" as CalMath

WidgetHost {
    id: root
    configKey: "calendarWindows"
    defaultPos: Qt.point(420, 440)
    tile: WidgetSizes.large

    readonly property string _serif: "Noto Serif Display"

    readonly property int startDay: (SettingsConfig.widgets.calendarWindowsMonday ?? true) ? 1 : 0
    readonly property bool showFooter: SettingsConfig.widgets.calendarWindowsFooter ?? true

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

    readonly property var weekLetters: {
        const base = ["S", "M", "T", "W", "T", "F", "S"]
        const out = []
        for (let i = 0; i < 7; i++)
            out.push(base[(i + root.startDay) % 7])
        return out
    }

    readonly property var nextHoliday: {
        ServiceClock.date
        const up = CalMath.upcomingHolidays(ServiceClock.holidayData, new Date(), 1)
        return up.length > 0 ? up[0] : null
    }

    optionsComponent: Component {
        CalendarOptionList {
            model: [{ key: "calendarWindowsMonday", label: "Start on Monday", sub: "Off starts the week on Sunday", def: true },
                    { key: "calendarWindowsFooter", label: "Show next holiday", sub: "A line under the building", def: true }]
        }
    }

    WidgetCard {
        anchors.fill: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: parent.pad
            anchors.bottomMargin: parent.pad
            spacing: 8

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                CustomText {
                    content: ServiceClock.month
                    size: 28
                    weight: 600
                    family: root._serif
                    renderType: Text.QtRendering
                }
                Item { Layout.fillWidth: true }
                CustomText {
                    content: ServiceClock.year
                    size: 12
                    weight: 500
                    customColor: Colors.surfaceVariantText
                }
            }

            CustomText {
                Layout.fillWidth: true
                Layout.topMargin: -6
                content: root.daysLeft === 0 ? "lights on for " + root.today + " nights · last one tonight"
                    : "lights on for " + root.today + " nights · " + root.daysLeft + " to go"
                size: 11
                weight: 400
                customColor: Colors.surfaceVariantText
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: root.weekLetters
                    CustomText {
                        required property string modelData
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        content: modelData
                        size: 10
                        weight: 600
                        customColor: Colors.outline
                    }
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: 5
                columnSpacing: 6

                Repeater {
                    model: root.cells

                    delegate: Item {
                        id: cell
                        required property var modelData

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 1

                        readonly property bool inMonth: cell.modelData.isCurrentMonth
                        readonly property bool isToday: cell.modelData.isToday
                        readonly property bool past: cell.inMonth && !cell.isToday && cell.modelData.day < root.today
                        readonly property bool holiday: cell.inMonth && cell.modelData.isHoliday
                        readonly property string holidayName: cell.holiday && cell.modelData.info.length > 0
                            ? cell.modelData.info[0].name : ""

                        opacity: cell.inMonth ? 1 : 0

                        Rectangle {
                            visible: cell.isToday
                            anchors.centerIn: pane
                            width: pane.width + 14
                            height: pane.height + 14
                            radius: 10
                            color: Qt.alpha(Colors.tertiary, 0.14)
                        }

                        Rectangle {
                            visible: cell.isToday
                            anchors.centerIn: pane
                            width: pane.width + 6
                            height: pane.height + 6
                            radius: 7
                            color: Qt.alpha(Colors.tertiary, 0.3)
                        }

                        Rectangle {
                            id: pane
                            anchors.fill: parent
                            radius: 5
                            clip: true
                            color: cell.isToday ? Colors.tertiary
                                : cell.past ? Qt.alpha(Colors.primaryContainer, 0.42)
                                : Qt.alpha(Colors.surfaceContainerHighest, 0.55)

                            readonly property color mullion: cell.isToday ? Qt.alpha(Colors.tertiaryText, 0.25)
                                : Qt.alpha(Colors.surface, cell.past ? 0.35 : 0.5)

                            Rectangle {
                                x: Math.round(pane.width / 2)
                                width: 1
                                height: pane.height
                                color: pane.mullion
                            }

                            Rectangle {
                                y: Math.round(pane.height / 2)
                                width: pane.width
                                height: 1
                                color: pane.mullion
                            }

                            Rectangle {
                                visible: cell.holiday
                                width: pane.width
                                height: Math.max(6, pane.height * 0.34)
                                topLeftRadius: 4
                                topRightRadius: 4
                                bottomLeftRadius: 10
                                bottomRightRadius: 10
                                color: Colors.tertiaryContainer
                            }

                            CustomText {
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.rightMargin: 4
                                anchors.bottomMargin: 1
                                content: String(cell.modelData.day)
                                size: 10
                                weight: cell.isToday ? 700 : 500
                                customColor: cell.isToday ? Colors.tertiaryText
                                    : cell.past ? Qt.alpha(Colors.primary, 0.9)
                                    : Qt.alpha(Colors.surfaceVariantText, 0.75)
                            }
                        }

                        CustomToolTip {
                            visible: cellHover.containsMouse && cell.holidayName !== ""
                            content: cell.holidayName + " · " + cell.modelData.day
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

            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                visible: root.showFooter
                implicitHeight: 2
                radius: 1
                color: Qt.alpha(Colors.surfaceText, 0.14)
            }

            RowLayout {
                Layout.fillWidth: true
                visible: root.showFooter
                spacing: 8

                Rectangle {
                    implicitWidth: 14
                    implicitHeight: 8
                    topLeftRadius: 3
                    topRightRadius: 3
                    bottomLeftRadius: 6
                    bottomRightRadius: 6
                    color: Colors.tertiaryContainer
                }
                CustomText {
                    Layout.fillWidth: true
                    content: root.nextHoliday ? "Next: " + root.nextHoliday.name : "No more holidays this year"
                    size: 11
                    weight: 400
                    customColor: Colors.surfaceVariantText
                }
                CustomText {
                    visible: root.nextHoliday !== null
                    content: root.nextHoliday
                        ? (root.nextHoliday.days === 1 ? "tomorrow" : "in " + root.nextHoliday.days + " days") : ""
                    size: 11
                    weight: 600
                    customColor: Colors.tertiary
                }
            }
        }
    }
}
