// Ported from Nebula's Widgets/MusicPosterWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "musicPoster"
    tile: Qt.size(WidgetSizes.span(2), WidgetSizes.span(3))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(2, 3)
    maxSpan: Qt.size(3, 4)
    defaultPos: Qt.point(475, 165)
    backdrop: false

    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"

    MusicNow { id: m; preview: root.preview }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(200, 310)

        Rectangle {
            anchors.fill: parent
            radius: WidgetSizes.radius + 4
            color: Colors.primary
            clip: true

            Item {
                anchors.fill: parent
                anchors.margins: root.sw < 260 ? 16 : 20

                CustomText {
                    visible: root.sw >= 260 || m.albumShown === ""
                    content: m.source.toUpperCase()
                    size: 10
                    weight: 700
                    font.letterSpacing: 1.6
                    customColor: Colors.primaryText
                }
                CustomText {
                    anchors.right: parent.right
                    width: Math.min(implicitWidth, parent.width * 0.6)
                    horizontalAlignment: Text.AlignRight
                    content: m.albumShown.toUpperCase()
                    size: 10
                    weight: 700
                    font.letterSpacing: 1.6
                    customColor: Colors.primaryText
                }

                Text {
                    id: headline
                    y: 22
                    width: parent.width
                    height: parent.height - 22 - footer.height - 12
                    text: m.title.toUpperCase()
                    font.family: root.display
                    font.pixelSize: 76
                    lineHeight: 0.86
                    wrapMode: Text.WordWrap
                    fontSizeMode: Text.Fit
                    minimumPixelSize: 26
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignTop
                    renderType: Text.QtRendering
                    color: Colors.primaryText
                }

                Column {
                    id: footer
                    anchors.bottom: parent.bottom
                    width: parent.width
                    spacing: 12

                    Row {
                        width: parent.width
                        spacing: 12
                        MusicArt {
                            visible: root.sw >= 260
                            width: 54
                            height: 54
                            radius: 14
                            source: m.artUrl
                            border.width: 3
                            border.color: Colors.primaryText
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - (root.sw >= 260 ? 66 : 0) - 60
                            CustomText { width: parent.width; content: m.artist; size: 15; weight: 700; customColor: Colors.primaryText }
                            CustomText { content: m.elapsedText + " / " + m.lengthText; size: 12; weight: 500; customColor: Qt.alpha(Colors.primaryText, 0.75) }
                        }
                        MusicButton {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 48
                            height: 48
                            radius: 16
                            icon: m.playing ? "pause" : "play_arrow"
                            iconSize: 24
                            fg: Colors.primary
                            bg: Colors.primaryText
                            onClicked: m.toggle()
                        }
                    }

                    Item {
                        width: parent.width
                        height: 22
                        Rectangle {
                            y: 8
                            width: parent.width
                            height: 4
                            radius: 2
                            color: Qt.alpha(Colors.primaryText, 0.25)
                        }
                        Rectangle {
                            y: 8
                            width: parent.width * m.progress
                            height: 4
                            radius: 2
                            color: Colors.primaryText
                        }
                        Rectangle {
                            x: parent.width * m.progress - 2
                            width: 4
                            height: 20
                            radius: 2
                            color: Colors.primaryText
                        }
                        Repeater {
                            model: 10
                            delegate: Rectangle {
                                required property int index
                                x: (parent.width - 2) * index / 9
                                y: 16
                                width: 2
                                height: index % 3 === 0 ? 6 : 3
                                radius: 1
                                color: Colors.primaryText
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            enabled: m.canSeek
                            cursorShape: m.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: mouse => m.seek(mouse.x / width)
                        }
                    }
                }
            }
        }
    }
}
