// Ported from Nebula's Widgets/SysCockpitWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "sysCockpit"
    tile: Qt.size(WidgetSizes.span(4), WidgetSizes.span(2.5))
    resizable: true
    minSpan: Qt.size(4, 2.5)
    maxSpan: Qt.size(6, 3.5)
    backdropRadius: (WidgetSizes.radius + 6) * designStage.k
    defaultPos: Qt.point(145, 165)

    readonly property var si: root.preview ? PreviewData : ServiceSystemInfo
    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"

    Component.onCompleted: root.si.retain()
    Component.onDestruction: root.si.release()

    component SmallDial: Item {
        id: dial
        property real value: 0
        property string label: ""
        property color tint: Colors.primary
        width: 104
        height: 90

        MeterSpeedo {
            width: parent.width
            height: 58
            thickness: 8
            showTicks: false
            value: dial.value
            color: dial.tint
            trackColor: Colors.surfaceContainerHigh
            hubHole: Colors.surfaceContainerLowest
        }
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            spacing: 4
            CustomText {
                content: Math.round(dial.value * 100)
                family: SettingsConfig.general?.displayFont || "Titan One"
                renderType: Text.QtRendering
                size: 18
                weight: 400
            }
            CustomText {
                anchors.baseline: parent.children[0].baseline
                content: dial.label
                size: 12
                weight: 600
                customColor: Colors.outline
            }
        }
    }

    component Lamp: Rectangle {
        property string text: ""
        property bool lit: false
        width: lampText.implicitWidth + 16
        height: 22
        radius: 6
        color: lit ? Colors.errorContainer : Colors.surfaceContainer
        CustomText {
            id: lampText
            anchors.centerIn: parent
            content: parent.text
            size: 12
            weight: 700
            font.letterSpacing: 1
            customColor: parent.lit ? Colors.errorContainerText : Colors.outlineVariant
        }
    }

    component Strip: Row {
        id: strip
        property string lo: ""
        property string hi: ""
        property real value: 0
        property bool fill: false
        property color tint: Colors.surfaceText
        spacing: 7
        CustomText { anchors.verticalCenter: parent.verticalCenter; content: strip.lo; size: 12; weight: 700; customColor: Colors.outline }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 56
            height: 6
            radius: 3
            color: Colors.surfaceContainerHigh
            Rectangle {
                visible: strip.fill
                width: parent.width * Math.max(0, Math.min(1, strip.value))
                height: parent.height
                radius: 3
                color: strip.tint
            }
            Rectangle {
                visible: !strip.fill
                x: parent.width * Math.max(0, Math.min(1, strip.value)) - 1.5
                y: -4
                width: 3
                height: 14
                radius: 1.5
                color: strip.tint
            }
        }
        CustomText { anchors.verticalCenter: parent.verticalCenter; content: strip.hi; size: 12; weight: 700; customColor: Colors.outline }
    }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(420, 270)

        Rectangle {
            anchors.fill: parent
            radius: WidgetSizes.radius + 8
            color: Colors.surfaceContainerLowest
            border.width: 1
            border.color: Colors.surfaceContainerHigh

            SmallDial {
                x: 12
                y: 50
                value: root.si.memUsage
                label: "RAM %"
                tint: Colors.tertiary
            }

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 14
                width: 170
                height: 160

                MeterSpeedo {
                    width: parent.width
                    height: 98
                    thickness: 12
                    warnAt: 0.8
                    value: root.si.cpuUsage
                    color: Colors.primary
                    trackColor: Colors.surfaceContainerHigh
                    needleColor: Colors.error
                    hubHole: Colors.surfaceContainerLowest
                }

                Column {
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 94
                    spacing: 0
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        CustomText {
                            content: Math.round(root.si.cpuUsage * 100)
                            family: root.display
                            renderType: Text.QtRendering
                            size: 32
                            weight: 400
                        }
                        CustomText {
                            anchors.baseline: parent.children[0].baseline
                            content: "%"
                            family: root.display
                            renderType: Text.QtRendering
                            size: 16
                            weight: 400
                            customColor: Colors.outline
                        }
                    }
                    CustomText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        content: "CPU"
                        size: 12
                        weight: 700
                        font.letterSpacing: 1.5
                        customColor: Colors.outline
                    }
                }
            }

            SmallDial {
                anchors.right: parent.right
                anchors.rightMargin: 12
                y: 50
                value: root.si.gpuUsage
                label: "GPU %"
                tint: Colors.secondary
            }

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 18
                spacing: 16

                Strip {
                    lo: "C"
                    hi: "H  " + Math.round(root.si.cpuTemp) + "°"
                    value: (root.si.cpuTemp - 30) / 70
                }
                Strip {
                    lo: "DISK F"
                    hi: "E"
                    fill: true
                    value: root.si.diskUsage
                    tint: root.si.diskUsage >= 0.85 ? Colors.error : Colors.primary
                }
            }

            Row {
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: 16
                spacing: 6
                Lamp { text: "HOT"; lit: root.si.cpuTemp >= 85 }
                Lamp { text: "DISK"; lit: root.si.diskUsage >= 0.85 }
                Lamp { text: "MEM"; lit: root.si.memUsage >= 0.9 }
            }
        }
    }
}
