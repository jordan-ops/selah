// Ported from Nebula's Widgets/MusicWaveformWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "musicWaveform"
    tile: Qt.size(WidgetSizes.span(4), WidgetSizes.span(1.5))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(4, 1.5)
    maxSpan: Qt.size(8, 2)
    backdropRadius: WidgetSizes.radius * designStage.k
    defaultPos: Qt.point(1025, 605)

    MusicNow { id: m; preview: root.preview }

    readonly property int bars: Math.max(24, Math.floor((root.sw - 40) / 7))
    readonly property var cells: {
        const out = []
        const k = ServiceMusicWave.captured
        const seedKey = ServiceMusicWave.seed
        for (let i = 0; i < root.bars; i++)
            out.push(root.preview ? { v: 0.3 + 0.6 * Math.abs(Math.sin(i * 0.37) * 0.6 + Math.sin(i * 0.11 + 1) * 0.4), real: true }
                                  : ServiceMusicWave.cell(i, root.bars))
        return out
    }

    Component.onCompleted: if (!root.preview) ServiceMusicWave.retain()
    Component.onDestruction: if (!root.preview) ServiceMusicWave.release()

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(420, 145)

        WidgetCard {
            anchors.fill: parent

            Row {
                id: head
                x: 18; y: 16
                width: parent.width - 36
                spacing: 12

                MusicArt {
                    width: 46
                    height: 46
                    radius: 14
                    source: m.artUrl
                }
                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: head.width - 46 - controls.width - 24
                    CustomText { width: parent.width; content: m.title; size: 15; weight: 700 }
                    CustomText { width: parent.width; content: [m.artist, m.albumShown].filter(s => s !== "").join(" · "); size: 12; customColor: Colors.surfaceVariantText }
                }
                Row {
                    id: controls
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    MusicButton { anchors.verticalCenter: parent.verticalCenter; icon: "skip_previous"; iconSize: 22; onClicked: m.previous() }
                    MusicButton { width: 48; height: 48; radius: 16; icon: m.playing ? "pause" : "play_arrow"; iconSize: 24; fg: Colors.primaryText; bg: Colors.primary; onClicked: m.toggle() }
                    MusicButton { anchors.verticalCenter: parent.verticalCenter; icon: "skip_next"; iconSize: 22; onClicked: m.next() }
                }
            }

            Item {
                id: wave
                x: 20
                y: 78
                width: parent.width - 40
                height: parent.height - 78 - 24

                Row {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Repeater {
                        model: root.cells
                        delegate: Rectangle {
                            required property var modelData
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: (wave.width - (root.bars - 1) * 3) / root.bars
                            height: Math.max(4, wave.height * modelData.v)
                            radius: width / 2
                            color: index / root.bars < m.progress ? Colors.primary
                                 : modelData.real ? Colors.surfaceContainerHighest : Qt.alpha(Colors.surfaceContainerHighest, 0.6)
                        }
                    }
                }

                Rectangle {
                    x: wave.width * m.progress - 1.5
                    width: 3
                    height: wave.height
                    radius: 1.5
                    color: Colors.surfaceText
                }
                Rectangle {
                    x: Math.max(0, Math.min(wave.width - width, wave.width * m.progress - width / 2))
                    y: -12
                    width: bubble.implicitWidth + 14
                    height: 18
                    radius: 9
                    color: Colors.surfaceText
                    CustomText { id: bubble; anchors.centerIn: parent; content: m.elapsedText; size: 10; weight: 700; customColor: Colors.surface }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: m.canSeek
                    cursorShape: m.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => m.seek(mouse.x / width)
                }
            }

            CustomText { x: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 8; content: "0:00"; size: 10; customColor: Colors.outline }
            CustomText { anchors.right: parent.right; anchors.rightMargin: 20; anchors.bottom: parent.bottom; anchors.bottomMargin: 8; content: m.remainingText; size: 10; customColor: Colors.outline }
        }
    }
}
