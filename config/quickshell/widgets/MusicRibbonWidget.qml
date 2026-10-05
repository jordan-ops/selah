// Ported from Nebula's Widgets/MusicRibbonWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "musicRibbon"
    tile: Qt.size(WidgetSizes.span(1), WidgetSizes.span(4))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(1, 4)
    maxSpan: Qt.size(1, 6)
    defaultPos: Qt.point(35, 165)
    backdropRadius: root.width / 2

    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"

    MusicNow { id: m; preview: root.preview }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(90, 420)

        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: WidgetSizes.cardColor

            MusicArt {
                id: art
                anchors.horizontalCenter: parent.horizontalCenter
                y: 10
                width: parent.width - 20
                height: width
                radius: width / 2
                source: m.artUrl
            }

            Item {
                id: mid
                anchors.top: art.bottom
                anchors.topMargin: 14
                anchors.bottom: time.top
                anchors.bottomMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                width: parent.width - 24

                Rectangle {
                    x: 6
                    width: 6
                    height: parent.height
                    radius: 3
                    color: Colors.surfaceContainerHighest
                    Rectangle {
                        anchors.bottom: parent.bottom
                        width: parent.width
                        height: parent.height * m.progress
                        radius: 3
                        color: Colors.primary
                    }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        enabled: m.canSeek
                        onClicked: mouse => m.seek(1 - (mouse.y - 8) / (height - 16))
                    }
                }

                Item {
                    x: 18
                    width: parent.width - 18
                    height: parent.height
                    clip: true
                    CustomText {
                        anchors.centerIn: parent
                        rotation: -90
                        width: parent.height
                        horizontalAlignment: Text.AlignHCenter
                        content: m.title
                        family: root.display
                        renderType: Text.QtRendering
                        size: 18
                        weight: 400
                    }
                }
            }

            CustomText {
                id: time
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: controls.top
                anchors.bottomMargin: 8
                content: m.elapsedText
                size: 12
                weight: 700
                customColor: Colors.primary
            }

            Column {
                id: controls
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 12
                spacing: 4
                MusicButton { anchors.horizontalCenter: parent.horizontalCenter; width: 44; height: 40; icon: "skip_previous"; iconSize: 22; onClicked: m.previous() }
                MusicButton { anchors.horizontalCenter: parent.horizontalCenter; width: 62; height: 62; icon: m.playing ? "pause" : "play_arrow"; iconSize: 28; fg: Colors.primaryText; bg: Colors.primary; onClicked: m.toggle() }
                MusicButton { anchors.horizontalCenter: parent.horizontalCenter; width: 44; height: 40; icon: "skip_next"; iconSize: 22; onClicked: m.next() }
            }
        }
    }
}
