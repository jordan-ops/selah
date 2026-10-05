// Ported from Nebula's Widgets/MusicGlanceWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick
import QtQuick.Effects

WidgetHost {
    id: root
    configKey: "musicGlance"
    tile: Qt.size(WidgetSizes.span(3), WidgetSizes.span(1))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(3, 1)
    maxSpan: Qt.size(5, 1)
    defaultPos: Qt.point(695, 935)
    backdrop: false

    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property bool showControls: hover.hovered || root.preview

    MusicNow { id: m; preview: root.preview }

    HoverHandler { id: hover }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(310, 90)

        Item {
            id: textBlock
            anchors.fill: parent
            layer.enabled: true
            layer.textureSize: Qt.size(width * Math.max(1, designStage.k), height * Math.max(1, designStage.k))
            layer.effect: MultiEffect {
                shadowEnabled: true
                shadowColor: Qt.rgba(0, 0, 0, 0.7)
                shadowBlur: 0.6
                shadowVerticalOffset: 2
                shadowHorizontalOffset: 0
            }

            Row {
                id: line
                y: 14
                width: parent.width
                spacing: 10
                CustomText {
                    id: title
                    width: Math.min(implicitWidth, line.width * 0.7)
                    content: m.title
                    family: root.display
                    renderType: Text.QtRendering
                    size: 26
                    weight: 400
                }
                CustomText {
                    anchors.baseline: title.baseline
                    width: line.width - title.width - 10
                    content: m.artist
                    size: 14
                    weight: 500
                    customColor: Colors.surfaceVariantText
                }
            }

            Row {
                y: 56
                spacing: 10
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 180
                    height: 3
                    radius: 1.5
                    color: Qt.alpha(Colors.surfaceText, 0.25)
                    Rectangle {
                        width: parent.width * m.progress
                        height: parent.height
                        radius: 1.5
                        color: Colors.primary
                    }
                }
                CustomText {
                    anchors.verticalCenter: parent.verticalCenter
                    content: m.elapsedText
                    size: 12
                    weight: 600
                    customColor: Colors.primary
                }
                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0
                    opacity: root.showControls ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { EffectsAnim {} }
                    MusicButton { width: 30; height: 30; icon: "skip_previous"; iconSize: 18; onClicked: m.previous() }
                    MusicButton { width: 30; height: 30; icon: m.playing ? "pause" : "play_arrow"; iconSize: 20; fg: Colors.primary; onClicked: m.toggle() }
                    MusicButton { width: 30; height: 30; icon: "skip_next"; iconSize: 18; onClicked: m.next() }
                }
            }
        }
    }
}
