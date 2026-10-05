// Ported from Nebula's Widgets/MusicCapsuleWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "musicCapsule"
    tile: Qt.size(WidgetSizes.span(3), WidgetSizes.span(1))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(3, 1)
    maxSpan: Qt.size(6, 1)
    defaultPos: Qt.point(145, 935)
    backdropRadius: root.height / 2

    readonly property int cells: 20

    MusicNow { id: m; preview: root.preview }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(310, 90)

        Rectangle {
            anchors.fill: parent
            radius: height / 2
            color: WidgetSizes.cardColor

            Item {
                id: disc
                x: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height - 26
                height: width

                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: Colors.primary
                }
                MusicArt {
                    anchors.fill: parent
                    anchors.margins: 4
                    radius: width / 2
                    source: m.artUrl
                    RotationAnimation on rotation {
                        from: 0
                        to: 360
                        duration: 12000
                        loops: Animation.Infinite
                        running: m.playing && !root.preview
                    }
                }
            }

            Column {
                anchors.left: disc.right
                anchors.leftMargin: 12
                anchors.right: next.left
                anchors.rightMargin: 6
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                CustomMarqueeText {
                    width: parent.width
                    content: m.title + (m.artist !== "" ? "  —  " + m.artist : "")
                    size: 14
                    weight: 600
                    scrolling: m.playing
                }
                Row {
                    id: caps
                    width: parent.width
                    spacing: 3
                    readonly property int lit: Math.round(m.progress * root.cells)
                    Repeater {
                        model: root.cells
                        delegate: Rectangle {
                            required property int index
                            width: (caps.width - 3 * (root.cells - 1)) / root.cells
                            height: 6
                            radius: 3
                            color: index >= caps.lit ? Colors.surfaceContainerHighest
                                 : index === caps.lit - 1 ? Colors.tertiary : Colors.primary
                        }
                    }
                    MouseArea {
                        width: caps.width
                        height: 18
                        y: -6
                        enabled: m.canSeek
                        onClicked: mouse => m.seek(mouse.x / width)
                    }
                }
            }

            MusicButton {
                id: next
                visible: root.sw >= 400
                width: visible ? 40 : 0
                anchors.right: play.left
                anchors.rightMargin: 2
                anchors.verticalCenter: parent.verticalCenter
                icon: "skip_next"
                iconSize: 22
                onClicked: m.next()
            }
            MusicButton {
                id: play
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                width: parent.height - 34
                height: width
                icon: m.playing ? "pause" : "play_arrow"
                iconSize: 24
                fg: Colors.primaryText
                bg: Colors.primary
                onClicked: m.toggle()
            }
        }
    }
}
