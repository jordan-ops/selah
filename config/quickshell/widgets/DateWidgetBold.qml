// Ported from Nebula's Widgets/DateWidgetBold.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import Quickshell
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

WidgetHost {
    id: root
    configKey: "dateWidget"
    tile: WidgetSizes.small
    defaultPos: Qt.point(300, 300)

    readonly property string d1: ServiceClock.date.charAt(0)
    readonly property string d2: ServiceClock.date.charAt(1)

    readonly property int _sz: 115
    readonly property real _overlap: -22
    readonly property real _ring: 6
    readonly property int _ringSteps: 12
    readonly property string _font: SettingsConfig.general.displayFont ?? "Titan One"

    WidgetCard {
        anchors.fill: parent

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0

            CustomText {
                Layout.alignment: Qt.AlignHCenter
                content: ServiceClock.day.toUpperCase()
                size: 11
                weight: 700
                color: Colors.primary
                font.letterSpacing: 3
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: -6
                spacing: root._overlap

                Item {
                    Layout.preferredWidth: _t1.implicitWidth
                    Layout.preferredHeight: _t1.implicitHeight

                    CustomText {
                        id: _t1
                        content: root.d1
                        size: root._sz
                        weight: 600
                        color: Colors.surfaceText
                        font.family: root._font
                        style: Text.Raised
                        styleColor: Colors.outline
                        layer.enabled: true
                        visible: false
                    }

                    Item {
                        id: _mask
                        width: _t1.implicitWidth
                        height: _t1.implicitHeight
                        layer.enabled: true
                        visible: false

                        CustomText {
                            content: root.d2
                            size: root._sz
                            weight: 600
                            color: "white"
                            font.family: root._font
                            x: _t1.implicitWidth + root._overlap
                        }

                        Repeater {
                            model: root._ringSteps

                            CustomText {
                                required property int index

                                readonly property real angle: index * 2 * Math.PI / root._ringSteps

                                content: root.d2
                                size: root._sz
                                weight: 600
                                color: "white"
                                font.family: root._font
                                x: _t1.implicitWidth + root._overlap + root._ring * Math.cos(angle)
                                y: root._ring * Math.sin(angle)
                            }
                        }
                    }

                    MultiEffect {
                        source: _t1
                        x: 0
                        y: 0
                        width: _t1.implicitWidth
                        height: _t1.implicitHeight
                        maskEnabled: true
                        maskSource: _mask
                        maskInverted: true
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }
                }

                CustomText {
                    content: root.d2
                    size: root._sz
                    weight: 600
                    color: Colors.primary
                    font.family: root._font
                    style: Text.Raised
                    styleColor: Colors.outline
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: -14
                spacing: 8

                CustomText {
                    content: ServiceClock.month
                    size: 13
                    weight: 600
                    color: Colors.surfaceText
                    font.family: root._font
                }

                Rectangle {
                    implicitWidth: 3
                    implicitHeight: 3
                    radius: 2
                    color: Colors.outline
                }

                CustomText {
                    content: ServiceClock.year
                    size: 13
                    weight: 600
                    color: Colors.outline
                    font.family: root._font
                }
            }
        }
    }
}
