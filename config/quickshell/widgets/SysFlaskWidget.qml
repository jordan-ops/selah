// Ported from Nebula's Widgets/SysFlaskWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick
import QtQuick.Shapes

WidgetHost {
    id: root
    configKey: "sysFlask"
    tile: Qt.size(WidgetSizes.span(2), WidgetSizes.span(2))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(2, 2)
    maxSpan: Qt.size(3, 3)
    backdropRadius: WidgetSizes.radius * designStage.k
    defaultPos: Qt.point(145, 165)

    readonly property var si: root.preview ? PreviewData : ServiceSystemInfo
    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    property real level: root.si.memUsage

    Behavior on level { SpatialAnim {} }

    readonly property real levelY: 140 - root.level * 118
    function wallX(y, left) {
        let off
        if (y <= 52)
            off = 12
        else if (y <= 126)
            off = 12 + (y - 52) / 74 * 36
        else
            off = 48
        return left ? 60 - off : 60 + off
    }
    readonly property string liquid: {
        const y = root.levelY
        const l = root.wallX(y, true), r = root.wallX(y, false)
        const m = (l + r) / 2
        let d = "M " + l + " " + y + " Q " + ((l + m) / 2) + " " + (y - 4) + " " + m + " " + y
              + " T " + r + " " + y
        if (y < 126)
            d += " L 108 126"
        d += " Q 112 140 98 140 L 22 140 Q 8 140 12 126"
        if (y < 52)
            d += " L 48 52 L 48 " + y
        else
            d += " L " + l + " " + y
        return d + " Z"
    }

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
                content: "MEMORY"
                size: 11
                weight: 700
                font.letterSpacing: 1.3
                customColor: Colors.outline
            }
            CustomText {
                anchors.right: parent.right
                anchors.rightMargin: parent.pad
                y: parent.pad
                content: Math.round(root.si.memUsage * 100) + "%"
                size: 11
                weight: 700
                customColor: Colors.outline
            }

            Item {
                anchors.horizontalCenter: parent.horizontalCenter
                y: 34
                width: 120
                height: 150
                scale: Math.min(1.1, (parent.height - 34 - 58) / 150)
                transformOrigin: Item.Top

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    ShapePath {
                        fillColor: Colors.tertiary
                        strokeColor: "transparent"
                        PathSvg { path: root.liquid }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Colors.outline
                        strokeWidth: 3
                        joinStyle: ShapePath.RoundJoin
                        PathSvg { path: "M 48 10 L 72 10 L 72 52 L 108 126 Q 112 140 98 140 L 22 140 Q 8 140 12 126 L 48 52 Z" }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Colors.outline
                        strokeWidth: 4
                        capStyle: ShapePath.RoundCap
                        PathSvg { path: "M 42 10 L 78 10" }
                    }
                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Colors.outlineVariant
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        PathSvg { path: "M 76 64 L 84 64 M 83 82 L 91 82 M 92 100 L 100 100" }
                    }
                }

                Repeater {
                    model: [Qt.point(44, 124), Qt.point(70, 116), Qt.point(58, 131)]
                    delegate: Rectangle {
                        required property point modelData
                        required property int index
                        visible: root.levelY < modelData.y - 6
                        x: modelData.x - width / 2
                        y: modelData.y - height / 2
                        width: [8, 6, 5][index]
                        height: width
                        radius: width / 2
                        color: Qt.lighter(Colors.tertiary, 1.25)
                    }
                }
            }

            Column {
                x: parent.pad
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.pad
                spacing: 1
                CustomText {
                    content: root.si.memUsedGb.toFixed(1) + " GB"
                    family: root.display
                    renderType: Text.QtRendering
                    size: 26
                    weight: 400
                }
                CustomText {
                    content: "of " + root.si.memTotalGb.toFixed(1) + " · " + (root.si.memCacheFrac * root.si.memTotalGb).toFixed(1) + " GB cached"
                    size: 11
                    customColor: Colors.surfaceVariantText
                }
            }
        }
    }
}
