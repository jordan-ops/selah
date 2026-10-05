// Ported from Nebula's Widgets/MusicTicketWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick
import QtQuick.Shapes

WidgetHost {
    id: root
    configKey: "musicTicket"
    tile: Qt.size(WidgetSizes.span(4), WidgetSizes.span(1.5))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(4, 1.5)
    maxSpan: Qt.size(6, 2)
    defaultPos: Qt.point(585, 605)
    backdrop: false

    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property bool compact: root.sh < 180
    readonly property real stub: root.compact ? 118 : 142
    readonly property real perf: root.sw - root.stub
    readonly property real notch: 11
    readonly property real r: 22
    readonly property color paper: Colors.surfaceContainerLowest
    readonly property color ink: Colors.surfaceText
    readonly property color accent: Colors.primary
    readonly property var bars: [3, 4, 2, 2, 2, 1, 2, 3, 2, 2, 4, 1, 2, 3, 3, 2, 2, 4, 1, 3, 1, 1, 3, 2, 1, 2, 4, 1]

    MusicNow { id: m; preview: root.preview }

    component Field: Column {
        id: fld
        property string k: ""
        property string v: ""
        spacing: 1
        CustomText { content: fld.k; size: 9; weight: 700; font.letterSpacing: 1.4; customColor: Colors.primary }
        CustomText { content: fld.v; size: 12; weight: 600; customColor: Colors.surfaceText; width: fld.width }
    }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(420, 145)

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                fillColor: root.paper
                strokeColor: Colors.outlineVariant
                strokeWidth: 1
                startX: root.r; startY: 0
                PathLine { x: root.perf - root.notch; y: 0 }
                PathArc { x: root.perf + root.notch; y: 0; radiusX: root.notch; radiusY: root.notch; direction: PathArc.Counterclockwise }
                PathLine { x: root.sw - root.r; y: 0 }
                PathArc { x: root.sw; y: root.r; radiusX: root.r; radiusY: root.r }
                PathLine { x: root.sw; y: root.sh - root.r }
                PathArc { x: root.sw - root.r; y: root.sh; radiusX: root.r; radiusY: root.r }
                PathLine { x: root.perf + root.notch; y: root.sh }
                PathArc { x: root.perf - root.notch; y: root.sh; radiusX: root.notch; radiusY: root.notch; direction: PathArc.Counterclockwise }
                PathLine { x: root.r; y: root.sh }
                PathArc { x: 0; y: root.sh - root.r; radiusX: root.r; radiusY: root.r }
                PathLine { x: 0; y: root.r }
                PathArc { x: root.r; y: 0; radiusX: root.r; radiusY: root.r }
            }
            ShapePath {
                strokeColor: Qt.alpha(root.ink, 0.35)
                strokeWidth: 2
                strokeStyle: ShapePath.DashLine
                dashPattern: [2, 2]
                fillColor: "transparent"
                startX: root.perf; startY: root.notch + 6
                PathLine { x: root.perf; y: root.sh - root.notch - 6 }
            }
        }

        Item {
            x: 22
            y: root.compact ? 14 : 18
            width: root.perf - 44
            height: root.sh - y * 2

            CustomText {
                content: "ADMIT ONE · " + (m.playing ? "NOW PLAYING" : "PAUSED")
                size: 10
                weight: 700
                font.letterSpacing: 2
                customColor: root.accent
            }
            CustomText {
                id: title
                y: root.compact ? 16 : 20
                width: parent.width
                content: m.title
                family: root.display
                renderType: Text.QtRendering
                size: root.compact ? 22 : 28
                weight: 400
                customColor: root.ink
            }
            CustomText {
                anchors.top: title.bottom
                width: parent.width
                content: m.artist
                size: 14
                weight: 500
                customColor: root.ink
            }
            Row {
                id: fields
                anchors.bottom: parent.bottom
                width: parent.width
                spacing: 14
                Field { width: (fields.width - 28) * 0.45; k: "ALBUM"; v: m.albumShown !== "" ? m.albumShown : "—" }
                Field { width: (fields.width - 28) * 0.35; k: "PLAYER"; v: m.source !== "" ? m.source : "—" }
                Field { width: (fields.width - 28) * 0.2; k: "LENGTH"; v: m.lengthText }
            }
        }

        Column {
            x: root.perf + 12
            y: root.compact ? 10 : 16
            width: root.stub - 24
            height: root.sh - y * 2
            spacing: root.compact ? 3 : 6

            CustomText {
                anchors.horizontalCenter: parent.horizontalCenter
                content: "TIME"
                size: 9
                weight: 700
                font.letterSpacing: 1.6
                customColor: root.accent
            }
            CustomText {
                anchors.horizontalCenter: parent.horizontalCenter
                content: m.elapsedText
                family: root.display
                renderType: Text.QtRendering
                size: root.compact ? 22 : 28
                weight: 400
                customColor: root.accent
            }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                height: root.compact ? 20 : 30
                spacing: root.compact ? 1.5 : 2
                Repeater {
                    model: root.bars
                    delegate: Rectangle {
                        required property int modelData
                        required property int index
                        width: root.compact ? Math.max(1, modelData * 0.8) : modelData
                        height: parent.height
                        color: index / root.bars.length < m.progress ? root.ink : Qt.alpha(root.ink, 0.3)
                    }
                }
            }
            Item { width: 1; height: root.compact ? 0 : 4 }
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 2
                MusicButton { width: 34; height: 34; icon: "skip_previous"; iconSize: 18; fg: root.ink; onClicked: m.previous() }
                MusicButton { width: 34; height: 34; icon: m.playing ? "pause" : "play_arrow"; iconSize: 18; fg: root.paper; bg: root.ink; onClicked: m.toggle() }
                MusicButton { width: 34; height: 34; icon: "skip_next"; iconSize: 18; fg: root.ink; onClicked: m.next() }
            }
        }
    }
}
