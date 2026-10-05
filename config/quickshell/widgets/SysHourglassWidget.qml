// Ported from Nebula's Widgets/SysHourglassWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick
import QtQuick.Shapes
import Quickshell.Io

WidgetHost {
    id: root
    configKey: "sysHourglass"
    tile: Qt.size(WidgetSizes.span(2), WidgetSizes.span(2))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(2, 2)
    maxSpan: Qt.size(3, 3)
    backdropRadius: WidgetSizes.radius * designStage.k
    defaultPos: Qt.point(1025, 165)

    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"

    // Previews read canned values and never start the pollers
    readonly property var si: root.preview ? PreviewData : ServiceSystemInfo

    Component.onCompleted: root.si.retain()
    Component.onDestruction: root.si.release()

    property real upSeconds: root.preview ? 22200 : 0
    property real dayFrac: 0.6

    readonly property int hours: Math.floor(root.upSeconds / 3600)
    readonly property int minutes: Math.floor((root.upSeconds % 3600) / 60)
    readonly property string since: Qt.formatTime(new Date(Date.now() - root.upSeconds * 1000), "hh:mm")

    readonly property real sandTop: 1 - root.dayFrac
    readonly property real sandBottom: root.dayFrac

    function refresh() {
        const d = new Date()
        root.dayFrac = (d.getHours() * 3600 + d.getMinutes() * 60 + d.getSeconds()) / 86400
        if (!root.preview)
            uptimeFile.reload()
    }

    FileView {
        id: uptimeFile
        path: "/proc/uptime"
        onLoaded: root.upSeconds = parseFloat(text().split(" ")[0]) || 0
    }

    Timer {
        interval: 60000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(200, 200)

        WidgetCard {
            anchors.fill: parent

            Item {
                id: glass
                x: parent.pad - 2
                anchors.verticalCenter: parent.verticalCenter
                width: 80
                height: 120

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    scale: 0.8
                    transformOrigin: Item.TopLeft

                    ShapePath {
                        fillColor: Colors.surfaceContainerHigh
                        strokeColor: Colors.outlineVariant
                        strokeWidth: 2
                        PathSvg { path: "M 22 12 L 78 12 Q 78 50 54 75 Q 78 100 78 138 L 22 138 Q 22 100 46 75 Q 22 50 22 12 Z" }
                    }
                    ShapePath {
                        fillColor: Colors.secondary
                        strokeColor: "transparent"
                        PathSvg {
                            readonly property real w: 16 * root.sandTop
                            path: root.sandTop <= 0.02 ? "" : "M " + (50 - w) + " " + (70 - 26 * root.sandTop) + " L " + (50 + w) + " " + (70 - 26 * root.sandTop) + " Q " + (50 + w * 0.6) + " 64 50 72 Q " + (50 - w * 0.6) + " 64 " + (50 - w) + " " + (70 - 26 * root.sandTop) + " Z"
                        }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Colors.secondary
                        strokeWidth: 2
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [1.5, 1.5]
                        PathSvg { path: "M 50 74 L 50 " + (136 - 36 * root.sandBottom) }
                    }
                    ShapePath {
                        fillColor: Colors.secondary
                        strokeColor: "transparent"
                        PathSvg {
                            readonly property real h: 8 + 36 * root.sandBottom
                            readonly property real w: 12 + 16 * root.sandBottom
                            path: "M " + (50 - w) + " 137 Q 50 " + (137 - h * 2) + " " + (50 + w) + " 137 Z"
                        }
                    }
                    ShapePath {
                        fillColor: Colors.outline
                        strokeColor: "transparent"
                        PathSvg { path: "M 16 4 L 84 4 Q 88 4 88 8 Q 88 12 84 12 L 16 12 Q 12 12 12 8 Q 12 4 16 4 Z M 16 138 L 84 138 Q 88 138 88 142 Q 88 146 84 146 L 16 146 Q 12 146 12 142 Q 12 138 16 138 Z" }
                    }
                }
            }

            Column {
                anchors.left: glass.right
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2
                CustomText { content: "UPTIME"; size: 11; weight: 700; font.letterSpacing: 1.3; customColor: Colors.outline }
                CustomText {
                    content: root.hours + " h"
                    family: root.display
                    renderType: Text.QtRendering
                    size: 34
                    weight: 400
                }
                CustomText {
                    content: root.minutes + " m"
                    family: root.display
                    renderType: Text.QtRendering
                    size: 22
                    weight: 400
                    customColor: Colors.surfaceVariantText
                }
                Item { width: 1; height: 6 }
                CustomText { content: "since " + root.since; size: 11; customColor: Colors.surfaceVariantText }
                CustomText { content: "sand = rest of day"; size: 11; customColor: Colors.outline }
            }
        }
    }
}
