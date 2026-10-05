// Ported from Nebula's Widgets/SysThermoWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "sysThermo"
    tile: Qt.size(WidgetSizes.span(2), WidgetSizes.span(2))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(2, 2)
    maxSpan: Qt.size(3, 3)
    backdropRadius: WidgetSizes.radius * designStage.k
    defaultPos: Qt.point(365, 165)

    readonly property var si: root.preview ? PreviewData : ServiceSystemInfo
    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property real temp: root.si.cpuTemp
    property real peak: root.preview ? 84 : 0
    readonly property real lo: 30
    readonly property real hi: 100
    function frac(t) { return Math.max(0, Math.min(1, (t - root.lo) / (root.hi - root.lo))) }

    onTempChanged: if (!root.preview) root.peak = Math.max(root.peak, root.temp)

    Component.onCompleted: root.si.retain()
    Component.onDestruction: root.si.release()

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(200, 200)

        WidgetCard {
            anchors.fill: parent

            Item {
                id: tube
                x: parent.pad - 4
                y: parent.pad
                width: 52
                height: parent.height - parent.pad * 2

                readonly property real topPad: 4
                readonly property real bulb: 40
                readonly property real track: height - bulb - topPad - 10

                Rectangle {
                    x: 12
                    y: tube.topPad
                    width: 22
                    height: tube.height - tube.bulb / 2 - tube.topPad
                    radius: 11
                    color: Colors.surfaceContainerHigh
                    border.width: 2
                    border.color: Colors.outline
                }
                Rectangle {
                    x: 3
                    y: tube.height - tube.bulb
                    width: tube.bulb
                    height: tube.bulb
                    radius: tube.bulb / 2
                    color: Colors.surfaceContainerHigh
                    border.width: 2
                    border.color: Colors.outline
                }
                Rectangle {
                    x: 18
                    width: 10
                    radius: 5
                    y: tube.topPad + 6 + tube.track * (1 - root.frac(root.temp))
                    height: tube.height - tube.bulb / 2 - y
                    color: root.temp >= 85 ? Colors.error : Colors.primary
                    Behavior on y { SpatialAnim {} }
                }
                Rectangle {
                    x: 11
                    y: tube.height - tube.bulb + 8
                    width: tube.bulb - 16
                    height: width
                    radius: width / 2
                    color: root.temp >= 85 ? Colors.error : Colors.primary
                }
                Repeater {
                    model: 8
                    delegate: Rectangle {
                        required property int index
                        x: 38
                        y: tube.topPad + 6 + tube.track * index / 7
                        width: index % 2 === 0 ? 8 : 5
                        height: 2
                        radius: 1
                        color: Colors.outlineVariant
                    }
                }
                Rectangle {
                    visible: root.peak > 0
                    x: 36
                    y: tube.topPad + 6 + tube.track * (1 - root.frac(root.peak)) - 1
                    width: 14
                    height: 3
                    radius: 1.5
                    color: Colors.error
                }
            }

            Column {
                anchors.left: tube.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.rightMargin: parent.pad
                y: parent.pad
                spacing: 2
                CustomText { content: "CPU TEMP"; size: 11; weight: 700; font.letterSpacing: 1.3; customColor: Colors.outline }
                CustomText {
                    content: Math.round(root.temp) + "°"
                    family: root.display
                    renderType: Text.QtRendering
                    size: Math.min(50, root.sh * 0.22)
                    weight: 400
                }
            }

            Column {
                anchors.left: tube.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.rightMargin: parent.pad
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.pad
                spacing: 6

                Repeater {
                    model: [
                        { k: "peak", v: Math.round(root.peak) + "°", c: Colors.error },
                        { k: "GPU", v: Math.round(root.si.gpuTemp) + "°", c: Colors.surfaceText },
                        { k: "state", v: root.temp >= 85 ? "hot" : root.temp >= 70 ? "warm" : "cool", c: Colors.surfaceText }
                    ]
                    delegate: Item {
                        required property var modelData
                        width: parent.width
                        height: 16
                        CustomText { content: modelData.k; size: 12; customColor: Colors.outline }
                        CustomText { anchors.right: parent.right; content: modelData.v; size: 12; weight: 600; customColor: modelData.c }
                    }
                }
            }
        }
    }
}
