// Ported from Nebula's Widgets/MusicTunerWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "musicTuner"
    tile: Qt.size(WidgetSizes.span(4), WidgetSizes.span(2))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(4, 2)
    maxSpan: Qt.size(6, 2)
    backdropRadius: WidgetSizes.radius * designStage.k
    defaultPos: Qt.point(585, 825)

    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property var marks: {
        const len = m.length > 0 ? m.length : 240
        const step = len > 600 ? 120 : 60
        const out = []
        for (let t = 0; t < len - step * 0.35; t += step)
            out.push({ t: t, f: t / len })
        out.push({ t: len, f: 1 })
        return out
    }
    property real knobSpin: 0

    MusicNow { id: m; preview: root.preview }

    component Knob: Item {
        id: knob
        property string label: ""
        property real turn: 0
        property bool labelLeft: false
        signal clicked()
        width: 110
        height: 56
        Rectangle {
            id: dial
            x: knob.labelLeft ? knob.width - 56 : 0
            width: 56
            height: 56
            radius: 28
            color: Colors.surfaceContainerHighest
            border.width: 5
            border.color: Colors.surfaceContainerHigh
            rotation: knob.turn
            Behavior on rotation { SpatialAnim {} }
            Rectangle {
                x: 26; y: 8
                width: 4; height: 13
                radius: 2
                color: Colors.primary
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: knob.clicked()
            }
        }
        CustomText {
            anchors.verticalCenter: parent.verticalCenter
            x: knob.labelLeft ? 0 : 66
            content: knob.label
            size: 10
            weight: 700
            font.letterSpacing: 1.6
            customColor: Colors.outline
        }
    }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(420, 200)

        WidgetCard {
            anchors.fill: parent

            Rectangle {
                id: lcd
                x: 16; y: 16
                width: parent.width - 32
                height: 42
                radius: 12
                color: Colors.surfaceContainerLowest
                border.width: 1
                border.color: Colors.surfaceContainerHigh

                Rectangle {
                    id: st
                    x: 12
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24; height: 18
                    radius: 4
                    color: m.playing ? Colors.primary : Colors.surfaceContainerHighest
                    CustomText { anchors.centerIn: parent; content: "ST"; size: 9; weight: 800; customColor: m.playing ? Colors.primaryText : Colors.outline }
                }
                CustomMarqueeText {
                    anchors.left: st.right
                    anchors.leftMargin: 10
                    anchors.right: time.left
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    content: m.title + (m.artist !== "" ? " · " + m.artist : "")
                    size: 18
                    weight: 400
                    customColor: Colors.primary
                    scrolling: m.playing
                }
                CustomText {
                    id: time
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    content: m.elapsedText
                    family: root.display
                    renderType: Text.QtRendering
                    size: 17
                    weight: 400
                    customColor: Colors.primaryContainer
                }
            }

            Item {
                id: band
                x: 20
                y: 68
                width: parent.width - 40
                height: 52

                Repeater {
                    model: root.marks
                    delegate: Item {
                        required property var modelData
                        required property int index
                        x: modelData.f * band.width
                        CustomText {
                            x: index === root.marks.length - 1 ? -implicitWidth : index === 0 ? 0 : -implicitWidth / 2
                            content: ServiceMusic.formatTime(modelData.t)
                            size: 10
                            weight: 600
                            customColor: Colors.outline
                        }
                        Rectangle { x: -1; y: 18; width: 2; height: 24; radius: 1; color: Colors.outline }
                    }
                }
                Repeater {
                    model: Math.max(0, Math.floor(band.width / 11))
                    delegate: Rectangle {
                        required property int index
                        x: index * 11
                        y: 18
                        width: 2
                        height: 14
                        radius: 1
                        color: Colors.outlineVariant
                    }
                }
                Rectangle {
                    y: 40
                    width: band.width * m.progress
                    height: 4
                    radius: 2
                    color: Colors.primaryContainer
                }
                Rectangle {
                    x: band.width * m.progress - 2
                    y: 12
                    width: 4
                    height: 40
                    radius: 2
                    color: Colors.error
                    Behavior on x { SpatialAnim {} }
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: m.canSeek
                    cursorShape: m.canSeek ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: mouse => m.seek(mouse.x / width)
                }
            }

            Knob {
                x: 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                label: "PREV"
                turn: -40 + root.knobSpin
                onClicked: { root.knobSpin -= 30; m.previous() }
            }
            MusicButton {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 18
                width: 118
                height: 46
                icon: m.playing ? "pause" : "play_arrow"
                label: m.playing ? "Pause" : "Play"
                labelSize: 14
                fg: Colors.primaryText
                bg: Colors.primary
                onClicked: m.toggle()
            }
            Knob {
                anchors.right: parent.right
                anchors.rightMargin: 16
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                label: "NEXT"
                labelLeft: true
                turn: 35 + root.knobSpin
                onClicked: { root.knobSpin += 30; m.next() }
            }
        }
    }
}
