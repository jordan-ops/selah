// Ported from Nebula's Widgets/MusicBentoWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "musicBento"
    tile: Qt.size(WidgetSizes.span(2), WidgetSizes.span(2))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(2, 2)
    maxSpan: Qt.size(3, 3)
    defaultPos: Qt.point(1245, 385)
    backdrop: false

    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property real gap: 10
    readonly property real cell: (Math.min(root.sw, root.sh) - root.gap) / 2
    readonly property real rad: root.cell * 0.2

    MusicNow { id: m; preview: root.preview }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(200, 200)

        MusicArt {
            width: root.cell
            height: root.cell
            radius: root.rad
            source: m.artUrl
        }

        Rectangle {
            x: root.cell + root.gap
            width: root.cell
            height: root.cell
            radius: root.rad
            color: Colors.secondaryContainer
            Column {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: root.cell * 0.11
                spacing: 2
                CustomText {
                    width: parent.width
                    content: m.title
                    family: root.display
                    renderType: Text.QtRendering
                    size: Math.max(13, root.cell * 0.14)
                    weight: 400
                    wrapMode: Text.WordWrap
                    maximumLineCount: 3
                    customColor: Colors.secondaryContainerText
                }
                CustomText { width: parent.width; content: m.artist; size: Math.max(10, root.cell * 0.09); customColor: Qt.alpha(Colors.secondaryContainerText, 0.8) }
            }
        }

        Rectangle {
            y: root.cell + root.gap
            width: root.cell
            height: root.cell
            topLeftRadius: root.rad
            topRightRadius: root.rad
            bottomRightRadius: root.rad
            bottomLeftRadius: area.pressed ? root.rad : root.cell * 0.48
            color: Colors.primary
            Behavior on bottomLeftRadius { SpatialAnim { speed: "fast" } }
            MaterialIconSymbol {
                anchors.centerIn: parent
                content: m.playing ? "pause" : "play_arrow"
                iconSize: root.cell * 0.42
                customColor: Colors.primaryText
            }
            MouseArea {
                id: area
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: m.toggle()
            }
        }

        Rectangle {
            x: root.cell + root.gap
            y: root.cell + root.gap
            width: root.cell
            height: root.cell
            radius: root.rad
            color: WidgetSizes.cardColor
            Column {
                anchors.fill: parent
                anchors.margins: root.cell * 0.11
                spacing: root.cell * 0.07
                CustomText {
                    content: m.elapsedText
                    family: root.display
                    renderType: Text.QtRendering
                    size: Math.max(18, root.cell * 0.22)
                    weight: 400
                }
                MeterSplitTrack {
                    width: parent.width
                    height: 6
                    stopDot: false
                    value: m.progress
                }
                Row {
                    width: parent.width
                    spacing: 6
                    MusicButton { width: (parent.width - 6) / 2; height: root.cell * 0.26; radius: 10; icon: "skip_previous"; iconSize: 18; bg: Colors.surfaceContainerHigh; onClicked: m.previous() }
                    MusicButton { width: (parent.width - 6) / 2; height: root.cell * 0.26; radius: 10; icon: "skip_next"; iconSize: 18; bg: Colors.surfaceContainerHigh; onClicked: m.next() }
                }
            }
        }
    }
}
