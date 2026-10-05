// Ported from Nebula's Widgets/MusicNeonWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick
import QtQuick.Effects

WidgetHost {
    id: root
    configKey: "musicNeon"
    tile: Qt.size(WidgetSizes.span(4), WidgetSizes.span(1.5))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(4, 1.5)
    maxSpan: Qt.size(6, 2)
    defaultPos: Qt.point(585, 385)
    backdrop: false

    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property bool compact: root.sh < 180
    readonly property color tube: Qt.lighter(Colors.primary, 1.25)

    MusicNow { id: m; preview: root.preview }

    component NeonButton: Rectangle {
        id: nb
        property string icon: ""
        signal clicked()
        width: 44
        height: 44
        radius: 22
        color: area.containsMouse ? Qt.alpha(Colors.primary, 0.18) : "transparent"
        border.width: 2
        border.color: Colors.primary
        MaterialIconSymbol {
            anchors.centerIn: parent
            content: nb.icon
            iconSize: 20
            customColor: Qt.lighter(Colors.primary, 1.25)
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: nb.clicked()
        }
    }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(420, 145)

        Rectangle {
            anchors.fill: parent
            radius: WidgetSizes.radius + 4
            color: Colors.surfaceContainerLowest
            clip: true

            Canvas {
                readonly property real res: Math.max(1, designStage.k)
                width: parent.width * res
                height: parent.height * res
                scale: 1 / res
                transformOrigin: Item.TopLeft
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.scale(res, res)
                    ctx.strokeStyle = Qt.alpha(Colors.surfaceContainer, 0.9)
                    ctx.lineWidth = 2
                    let row = 0
                    for (let y = 0; y < height; y += 25, row++) {
                        ctx.beginPath(); ctx.moveTo(0, y + 0.5); ctx.lineTo(width, y + 0.5); ctx.stroke()
                        for (let x = (row % 2) * 30; x < width; x += 60) {
                            ctx.beginPath(); ctx.moveTo(x + 0.5, y); ctx.lineTo(x + 0.5, y + 25); ctx.stroke()
                        }
                    }
                }
            }

            Item {
                id: glow
                anchors.fill: parent
                layer.enabled: true
                layer.textureSize: Qt.size(width * Math.max(1, designStage.k), height * Math.max(1, designStage.k))
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: Colors.primary
                    shadowBlur: 1.0
                    shadowScale: 1.02
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                    brightness: 0.05
                }

                CustomText {
                    x: 24; y: root.compact ? 12 : 20
                    content: m.playing ? "now playing" : "paused"
                    size: 13
                    weight: 700
                    font.italic: true
                    font.letterSpacing: 1.5
                    customColor: Qt.lighter(Colors.tertiary, 1.15)
                }
                CustomText {
                    id: title
                    x: 24; y: root.compact ? 28 : 40
                    width: parent.width - 48
                    content: m.title
                    family: root.display
                    renderType: Text.QtRendering
                    size: root.compact ? 28 : 38
                    weight: 400
                    customColor: Qt.lighter(Colors.primary, 1.35)
                }
                Text {
                    x: 24
                    anchors.top: title.bottom
                    width: parent.width - 48
                    text: m.artist.toUpperCase()
                    elide: Text.ElideRight
                    font.family: root.display
                    font.pixelSize: root.compact ? 14 : 18
                    renderType: Text.QtRendering
                    color: "transparent"
                    style: Text.Outline
                    styleColor: Qt.lighter(Colors.tertiary, 1.2)
                }
                Rectangle {
                    x: 24
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: root.compact ? 26 : 38
                    width: (parent.width - 48 - 150) * m.progress
                    height: 4
                    radius: 2
                    color: Qt.lighter(Colors.primary, 1.35)
                }
            }

            Rectangle {
                x: 24
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.compact ? 26 : 38
                width: parent.width - 48 - 150
                height: 4
                radius: 2
                z: -1
                color: Colors.surfaceContainerHigh
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -10
                    enabled: m.canSeek
                    onClicked: mouse => m.seek((mouse.x - 10) / (width - 20))
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.compact ? 10 : 18
                spacing: 8
                NeonButton { anchors.verticalCenter: parent.verticalCenter; width: root.compact ? 34 : 38; height: width; icon: "skip_previous"; onClicked: m.previous() }
                NeonButton { width: root.compact ? 40 : 44; height: width; icon: m.playing ? "pause" : "play_arrow"; onClicked: m.toggle() }
                NeonButton { anchors.verticalCenter: parent.verticalCenter; width: root.compact ? 34 : 38; height: width; icon: "skip_next"; onClicked: m.next() }
            }
        }
    }
}
