// Ported from Nebula's Widgets/MusicExpressiveWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick
import "shapes/" as MaterialShapes
import "shapes/shape-library.js" as ShapeLibrary

WidgetHost {
    id: root
    configKey: "musicExpressive"
    tile: Qt.size(WidgetSizes.span(3), WidgetSizes.span(2))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(3, 2)
    maxSpan: Qt.size(5, 2)
    backdropRadius: WidgetSizes.radius * designStage.k
    defaultPos: Qt.point(145, 605)

    readonly property bool narrow: root.sw < 400
    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"

    MusicNow { id: m; preview: root.preview }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(310, 200)

        WidgetCard {
            anchors.fill: parent

            MusicArt {
                id: art
                x: 14
                y: 14
                width: Math.min(parent.height - 28, parent.width * 0.4)
                height: width
                radius: 24
                source: m.artUrl
            }

            Item {
                anchors.left: art.right
                anchors.leftMargin: 16
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.top: parent.top
                anchors.topMargin: 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 10

                Rectangle {
                    id: chip
                    visible: chipText.content !== ""
                    width: Math.min(parent.width, chipText.implicitWidth + 18)
                    height: 22
                    radius: 11
                    color: Colors.secondaryContainer
                    CustomText {
                        id: chipText
                        anchors.centerIn: parent
                        width: Math.min(implicitWidth, chip.parent.width - 18)
                        content: [m.source, m.albumShown].filter(s => s !== "").join(" · ").toUpperCase()
                        size: 10
                        weight: 700
                        font.letterSpacing: 0.8
                        customColor: Colors.secondaryContainerText
                    }
                }

                CustomText {
                    id: title
                    y: 30
                    width: parent.width
                    content: m.title
                    family: root.display
                    renderType: Text.QtRendering
                    size: root.narrow ? 18 : 21
                    weight: 400
                }
                CustomText {
                    anchors.top: title.bottom
                    width: parent.width
                    content: m.artist
                    size: 13
                    customColor: Colors.surfaceVariantText
                }

                M3WavyProgressBar {
                    id: wave
                    y: 84
                    readonly property real res: Math.max(1, designStage.k)
                    width: parent.width * res
                    height: 14 * res
                    scale: 1 / res
                    transformOrigin: Item.TopLeft
                    progress: m.progress
                    activeThickness: 4 * res
                    trackThickness: 4 * res
                    stopSize: 4 * res
                    trackGap: 4 * res
                    waveAmplitude: m.playing ? 3 * res : 0
                    wavelength: 18 * res
                    activeColor: Colors.primary
                    trackColor: Colors.secondaryContainer

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        enabled: m.canSeek
                        cursorShape: m.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                        onClicked: mouse => m.seek(mouse.x / width)
                    }
                }
                CustomText {
                    y: wave.y + 14
                    content: m.elapsedText
                    size: 10
                    customColor: Colors.outline
                }
                CustomText {
                    y: wave.y + 14
                    anchors.right: parent.right
                    content: m.lengthText
                    size: 10
                    customColor: Colors.outline
                }

                Row {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6

                    MusicButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "skip_previous"
                        iconSize: 24
                        onClicked: m.previous()
                    }

                    Item {
                        width: root.narrow ? 50 : 60
                        height: width
                        HiResShape {
                            k: designStage.k
                            anchors.fill: parent
                            polygon: ShapeLibrary.get(m.playing ? "cookie9" : "circle")
                            color: Colors.primary
                        }
                        MaterialIconSymbol {
                            anchors.centerIn: parent
                            content: m.playing ? "pause" : "play_arrow"
                            iconSize: 28
                            customColor: Colors.primaryText
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: m.toggle()
                        }
                    }

                    MusicButton {
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "skip_next"
                        iconSize: 24
                        onClicked: m.next()
                    }
                    MusicButton {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.narrow
                        icon: "shuffle"
                        iconSize: 20
                        fg: m.shuffle ? Colors.tertiary : Colors.outline
                        onClicked: m.toggleShuffle()
                    }
                }
            }
        }
    }
}
