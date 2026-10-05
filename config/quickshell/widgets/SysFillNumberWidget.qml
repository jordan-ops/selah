// Ported from Nebula's Widgets/SysFillNumberWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "sysFillNumber"
    tile: Qt.size(WidgetSizes.span(2), WidgetSizes.span(2))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(2, 2)
    maxSpan: Qt.size(3, 3)
    backdropRadius: WidgetSizes.radius * designStage.k
    defaultPos: Qt.point(1245, 165)
    optionsComponent: fillOptions

    readonly property var si: root.preview ? PreviewData : ServiceSystemInfo
    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property string metric: SettingsConfig.widgets.sysFillMetric ?? "gpu"
    readonly property var info: {
        switch (root.metric) {
        case "cpu":  return { title: "CPU", v: root.si.cpuUsage, line: Math.round(root.si.cpuUsage * 100) + "% busy", sub: Math.round(root.si.cpuTemp) + " °C", tint: Colors.primary }
        case "ram":  return { title: "MEMORY", v: root.si.memUsage, line: root.si.memUsedGb.toFixed(1) + " GB used", sub: "of " + root.si.memTotalGb.toFixed(1) + " GB", tint: Colors.tertiary }
        case "disk": return { title: "DISK", v: root.si.diskUsage, line: Math.round(root.si.diskUsedGb) + " GB used", sub: Math.round(root.si.diskTotalGb - root.si.diskUsedGb) + " GB free", tint: root.si.diskUsage >= 0.85 ? Colors.error : Colors.primary }
        }
        return { title: "GPU", v: root.si.gpuUsage, line: Math.round(root.si.gpuUsage * 100) + "% busy", sub: root.si.gpuVramUsedGb.toFixed(1) + " GB VRAM · " + Math.round(root.si.gpuTemp) + " °C", tint: Colors.secondary }
    }
    readonly property int pct: Math.round(Math.max(0, Math.min(1, root.info.v)) * 100)
    property real fill: root.pct / 100

    Behavior on fill { SpatialAnim {} }

    Component.onCompleted: root.si.retain()
    Component.onDestruction: root.si.release()

    Component {
        id: fillOptions
        M3ButtonGroup {
            fillWidth: true
            model: [
                { value: "gpu", label: "GPU", icon: "developer_board" },
                { value: "cpu", label: "CPU", icon: "memory" },
                { value: "ram", label: "RAM", icon: "memory_alt" },
                { value: "disk", label: "Disk", icon: "hard_drive" }
            ]
            activeCheck: function(v) { return root.metric === v }
            onSegmentClicked: v => SettingsConfig.widgets = Object.assign({}, SettingsConfig.widgets, { sysFillMetric: v })
        }
    }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(200, 200)

        WidgetCard {
            anchors.fill: parent
            clip: true

            CustomText {
                x: parent.pad; y: parent.pad
                content: root.info.title
                size: 11
                weight: 700
                font.letterSpacing: 1.3
                customColor: Colors.outline
            }

            Item {
                id: numBox
                x: parent.pad - 6
                y: parent.pad + 18
                width: parent.width - x
                height: parent.height - y - 52

                CustomText {
                    id: outline
                    content: root.pct
                    family: root.display
                    renderType: Text.QtRendering
                    size: numBox.height * (root.pct >= 100 ? 0.72 : 0.97)
                    weight: 400
                    height: numBox.height
                    verticalAlignment: Text.AlignVCenter
                    customColor: "transparent"
                    style: Text.Outline
                    styleColor: Colors.outlineVariant
                }

                Item {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: parent.height * (0.12 + 0.76 * root.fill)
                    clip: true

                    CustomText {
                        y: parent.height - numBox.height
                        content: root.pct
                        family: root.display
                        renderType: Text.QtRendering
                        size: outline.size
                        weight: 400
                        height: numBox.height
                        verticalAlignment: Text.AlignVCenter
                        customColor: root.info.tint
                    }
                }
            }

            Column {
                x: parent.pad
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.pad
                CustomText { content: root.info.line; size: 14; weight: 700 }
                CustomText { content: root.info.sub; size: 11; customColor: Colors.surfaceVariantText }
            }
        }
    }
}
