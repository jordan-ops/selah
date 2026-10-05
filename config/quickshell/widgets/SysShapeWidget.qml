// Ported from Nebula's Widgets/SysShapeWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick
import "shapes/" as MaterialShapes
import "shapes/shape-library.js" as ShapeLibrary

WidgetHost {
    id: root
    configKey: "sysShape"
    tile: Qt.size(WidgetSizes.span(2), WidgetSizes.span(2))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(2, 2)
    maxSpan: Qt.size(3, 3)
    backdropRadius: WidgetSizes.radius * designStage.k
    defaultPos: Qt.point(805, 165)

    readonly property var si: root.preview ? PreviewData : ServiceSystemInfo
    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property real cpu: root.si.cpuUsage
    readonly property string mood: root.si.cpuTemp >= 85 || root.cpu >= 0.85 ? "hot" : root.cpu >= 0.3 ? "busy" : "idle"
    readonly property var moods: [
        { id: "idle", shape: "circle", label: "idle" },
        { id: "busy", shape: "cookie9", label: "busy" },
        { id: "hot", shape: "burst", label: "hot" }
    ]
    readonly property color moodColor: root.mood === "hot" ? Colors.error : root.mood === "busy" ? Colors.primary : Colors.secondaryContainer
    readonly property color moodInk: root.mood === "hot" ? Colors.errorText : root.mood === "busy" ? Colors.primaryText : Colors.secondaryContainerText

    Component.onCompleted: root.si.retain()
    Component.onDestruction: root.si.release()

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(200, 200)

        WidgetCard {
            anchors.fill: parent

            CustomText {
                x: parent.pad; y: parent.pad
                content: "CPU"
                size: 11
                weight: 700
                font.letterSpacing: 1.3
                customColor: Colors.outline
            }
            CustomText {
                anchors.right: parent.right
                anchors.rightMargin: parent.pad
                y: parent.pad
                content: root.si.cpuTemp > 0 ? Math.round(root.si.cpuTemp) + "°" : ""
                size: 11
                weight: 700
                customColor: Colors.outline
            }

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                y: parent.pad + 20
                width: Math.min(150, parent.height - parent.pad * 2 - 76)
                height: width

                HiResShape {
                    k: designStage.k
                    anchors.fill: parent
                    polygon: ShapeLibrary.get(root.moods.find(s => s.id === root.mood).shape)
                    color: root.moodColor
                }

                Column {
                    anchors.centerIn: parent
                    CustomText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        content: Math.round(root.cpu * 100)
                        family: root.display
                        renderType: Text.QtRendering
                        size: Math.max(22, parent.parent.width * 0.29)
                        weight: 400
                        customColor: root.moodInk
                    }
                    CustomText {
                        anchors.horizontalCenter: parent.horizontalCenter
                        content: "% LOAD"
                        size: 10
                        weight: 700
                        customColor: root.moodInk
                    }
                }
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.pad - 4
                spacing: 22

                Repeater {
                    model: root.moods
                    delegate: Column {
                        id: st
                        required property var modelData
                        readonly property bool on: st.modelData.id === root.mood
                        spacing: 2
                        HiResShape {
                            k: designStage.k
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 22
                            height: 22
                            polygon: ShapeLibrary.get(st.modelData.shape)
                            color: st.on ? root.moodColor : Colors.surfaceContainerHighest
                        }
                        CustomText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            content: st.modelData.label
                            size: 10
                            weight: st.on ? 700 : 400
                            customColor: st.on ? Colors.surfaceText : Colors.outline
                        }
                    }
                }
            }
        }
    }
}
