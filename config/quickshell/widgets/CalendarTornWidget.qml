// Ported from Nebula's Widgets/CalendarTornWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes

WidgetHost {
    id: root
    configKey: "calendarTorn"
    defaultPos: Qt.point(1120, 300)
    tile: WidgetSizes.small

    backdropMask: tornMask

    readonly property string _serif: SettingsConfig.general.displayFont
    readonly property real _tear: 10

    readonly property int startDay: (SettingsConfig.widgets.calendarTornMonday ?? true) ? 1 : 0
    readonly property bool showStrip: SettingsConfig.widgets.calendarTornStrip ?? true

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

    readonly property int todayColumn: {
        ServiceClock.date
        const now = new Date()
        return (now.getDay() - root.startDay + 7) % 7
    }

    readonly property string todayInfo: {
        for (let i = 0; i < root.cells.length; i++)
            if (root.cells[i].isToday && root.cells[i].isHoliday)
                return root.cells[i].info ?? ""
        return ""
    }

    readonly property string facePath: {
        const w = root.width
        const h = root.height
        const r = WidgetSizes.radius
        if (w <= 0 || h <= 0) return ""
        const n = Math.max(2, Math.round(w / (root._tear * 2)))
        const sr = w / (n * 2)
        let p = "M " + r + " 0 L " + (w - r) + " 0"
        p += " A " + r + " " + r + " 0 0 1 " + w + " " + r
        p += " L " + w + " " + h
        for (let i = 1; i <= n; i++)
            p += " A " + sr + " " + sr + " 0 0 0 " + (w - i * 2 * sr) + " " + h
        p += " L 0 " + r
        p += " A " + r + " " + r + " 0 0 1 " + r + " 0 Z"
        return p
    }

    optionsComponent: Component {
        ColumnLayout {
            spacing: 3

            Repeater {
                model: [{ key: "calendarTornMonday", label: "Start on Monday", sub: "Off starts the week on Sunday", def: true },
                        { key: "calendarTornStrip", label: "Show week strip", sub: "Row of weekday letters along the tear", def: true }]

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

    Shape {
        z: -2
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            fillColor: WidgetSizes.cardColor
            strokeWidth: 0
            strokeColor: "transparent"
            PathSvg { path: root.facePath }
        }
    }

    Item {
        id: maskSource
        anchors.fill: parent

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: "white"
                strokeWidth: 0
                strokeColor: "transparent"
                PathSvg { path: root.facePath }
            }
        }
    }

    Item {
        width: 0
        height: 0
        clip: true

        ShaderEffectSource {
            id: tornMask
            width: root.width
            height: root.height
            textureSize: Qt.size(root.width, root.height)
            sourceItem: maskSource
            hideSource: true
            live: true
        }
    }

    Shape {
        id: perforation
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        anchors.bottom: parent.bottom
        anchors.bottomMargin: root._tear + 9
        implicitHeight: 1
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: Qt.alpha(Colors.outline, 0.5)
            strokeWidth: 1
            strokeStyle: ShapePath.DashLine
            dashPattern: [1.5, 3]
            fillColor: "transparent"
            startX: 0
            startY: 0.5

            PathLine { x: perforation.width; y: 0.5 }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        anchors.topMargin: 16
        anchors.bottomMargin: root._tear + 18
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            spacing: 6

            CustomText {
                Layout.fillWidth: true
                content: ServiceClock.month.toUpperCase()
                size: 9
                weight: 700
                customColor: Colors.primary
                font.letterSpacing: 2
            }

            CustomText {
                content: ServiceClock.year
                size: 9
                weight: 600
                customColor: Colors.outline
                font.letterSpacing: 1
            }
        }

        CustomText {
            Layout.topMargin: 2
            content: String(parseInt(ServiceClock.date))
            size: 74
            weight: 700
            family: root._serif
            renderType: Text.QtRendering
        }

        CustomText {
            Layout.topMargin: -6
            content: ServiceClock.day.toUpperCase()
            size: 11
            weight: 700
            customColor: Colors.outline
            font.letterSpacing: 3
        }

        CustomText {
            Layout.topMargin: 2
            Layout.fillWidth: true
            visible: root.todayInfo !== ""
            content: root.todayInfo
            size: 10
            weight: 600
            customColor: Colors.tertiary
        }

        Item { Layout.fillHeight: true }

        RowLayout {
            Layout.fillWidth: true
            visible: root.showStrip
            spacing: 0

            Repeater {
                model: root.weekLetters

                delegate: Item {
                    id: letter
                    required property string modelData
                    required property int index

                    Layout.fillWidth: true
                    Layout.preferredHeight: 20

                    readonly property bool isToday: letter.index === root.todayColumn

                    Rectangle {
                        anchors.centerIn: parent
                        visible: letter.isToday
                        width: 19
                        height: 19
                        radius: 10
                        color: Colors.primary
                    }

                    CustomText {
                        anchors.centerIn: parent
                        content: letter.modelData
                        size: 10
                        weight: 700
                        customColor: letter.isToday ? Colors.primaryText : Colors.outline
                    }
                }
            }
        }
    }
}
