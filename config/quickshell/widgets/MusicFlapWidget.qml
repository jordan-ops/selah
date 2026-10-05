// Ported from Nebula's Widgets/MusicFlapWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "musicFlap"
    tile: Qt.size(WidgetSizes.span(4), WidgetSizes.span(1.5))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(4, 1.5)
    maxSpan: Qt.size(6, 2)
    defaultPos: Qt.point(1025, 825)
    backdrop: false

    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property bool compact: root.sh < 180
    readonly property real bigW: root.compact ? 22 : 26
    readonly property int bigCount: Math.max(1, Math.floor((root.sw - 40 + 3) / (root.bigW + 3)))
    readonly property int smallCount: Math.max(1, Math.floor((root.sw - 40 - 80) / 19))

    function fit(s, n) {
        const u = String(s).toUpperCase()
        return u.length > n ? u.slice(0, n - 1) + "…" : u
    }
    function cells(s, n) {
        const t = root.fit(s, n)
        const out = []
        for (let i = 0; i < n; i++)
            out.push(i < t.length ? t[i] : " ")
        return out
    }

    MusicNow { id: m; preview: root.preview }

    component Flap: Rectangle {
        id: flap
        property string ch: " "
        property string shown: " "
        property int order: 0
        property real px: 22
        property color ink: Colors.surfaceText
        property bool animate: true
        radius: 5
        color: flap.ch === " " && flap.shown === " " ? "transparent" : Colors.surfaceContainer

        onChChanged: {
            if (!flap.animate) {
                flap.shown = flap.ch
                return
            }
            flip.restart()
        }
        Component.onCompleted: flap.shown = flap.ch

        SequentialAnimation {
            id: flip
            PauseAnimation { duration: flap.order * 28 }
            NumberAnimation { target: face; property: "yScale"; to: 0; duration: 90; easing.type: Easing.InQuad }
            ScriptAction { script: flap.shown = flap.ch }
            NumberAnimation { target: face; property: "yScale"; to: 1; duration: 110; easing.type: Easing.OutQuad }
        }

        Item {
            id: face
            anchors.fill: parent
            property real yScale: 1
            transform: Scale { origin.y: face.height / 2; yScale: face.yScale }
            CustomText {
                anchors.centerIn: parent
                content: flap.shown
                family: SettingsConfig.general?.displayFont || "Titan One"
                renderType: Text.QtRendering
                size: flap.px
                weight: 400
                customColor: flap.ink
            }
        }
        Rectangle {
            visible: flap.color.a > 0
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1.5
            color: Colors.surfaceContainerLowest
        }
    }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(420, 145)

        Rectangle {
            anchors.fill: parent
            radius: WidgetSizes.radius
            color: Colors.surfaceContainerLowest
            border.width: 1
            border.color: Colors.surfaceContainer

            CustomText { x: 20; y: 16; content: m.playing ? "NOW PLAYING" : "PAUSED"; size: 10; weight: 700; font.letterSpacing: 1.8; customColor: Colors.outline }
            CustomText {
                anchors.right: parent.right
                anchors.rightMargin: 20
                y: 16
                content: m.source.toUpperCase()
                size: 10
                weight: 700
                font.letterSpacing: 1.8
                customColor: Colors.outline
            }

            Row {
                x: 20; y: root.compact ? 32 : 38
                spacing: 3
                Repeater {
                    model: root.cells(m.title, root.bigCount)
                    delegate: Flap {
                        required property string modelData
                        required property int index
                        width: root.bigW
                        height: root.compact ? 32 : 38
                        px: root.compact ? 18 : 22
                        ch: modelData
                        order: index
                        animate: !root.preview
                    }
                }
            }

            Row {
                x: 20; y: root.compact ? 72 : 86
                spacing: 2
                Repeater {
                    model: root.cells(m.artist, root.smallCount)
                    delegate: Flap {
                        required property string modelData
                        required property int index
                        width: 17
                        height: 25
                        px: 14
                        ch: modelData
                        order: index
                        ink: Colors.surfaceVariantText
                        animate: !root.preview
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 20
                y: root.compact ? 72 : 86
                spacing: 2
                Repeater {
                    model: m.elapsedText.padStart(5, " ").split("")
                    delegate: Flap {
                        required property string modelData
                        required property int index
                        width: modelData === ":" ? 8 : 17
                        height: 25
                        px: 14
                        ch: modelData
                        order: index
                        color: modelData === " " ? "transparent" : Colors.surfaceContainerHigh
                        ink: Colors.primary
                        animate: false
                    }
                }
            }

            Row {
                x: 20
                anchors.bottom: parent.bottom
                anchors.bottomMargin: root.compact ? 8 : 14
                width: parent.width - 40
                spacing: 6
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 3 * (root.compact ? 32 : 36) - 18
                    height: 4
                    radius: 2
                    color: Colors.surfaceContainer
                    Rectangle { width: parent.width * m.progress; height: 4; radius: 2; color: Colors.primary }
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        enabled: m.canSeek
                        onClicked: mouse => m.seek((mouse.x - 8) / (width - 16))
                    }
                }
                MusicButton { width: root.compact ? 32 : 36; height: width; icon: "skip_previous"; iconSize: 18; fg: Colors.surfaceVariantText; onClicked: m.previous() }
                MusicButton { width: root.compact ? 32 : 36; height: width; radius: 10; icon: m.playing ? "pause" : "play_arrow"; iconSize: 18; fg: Colors.primaryText; bg: Colors.primary; onClicked: m.toggle() }
                MusicButton { width: root.compact ? 32 : 36; height: width; icon: "skip_next"; iconSize: 18; fg: Colors.surfaceVariantText; onClicked: m.next() }
            }
        }
    }
}
