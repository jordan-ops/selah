// Ported from Nebula's Widgets/MusicTerminalWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "musicTerminal"
    tile: Qt.size(WidgetSizes.span(4), WidgetSizes.span(2))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(4, 2)
    maxSpan: Qt.size(6, 3)
    backdropRadius: 18 * designStage.k
    defaultPos: Qt.point(145, 385)

    readonly property bool compact: root.sh < 240
    readonly property int fs: root.compact ? 12 : 13
    readonly property string mono: "JetBrains Mono"
    readonly property int barCells: 28
    readonly property int litCells: Math.round(m.progress * root.barCells)
    readonly property real volume: root.preview ? 0.72 : (ServiceMusic.activePlayer?.volume ?? 0)
    readonly property int volLit: Math.round(root.volume * 10)
    readonly property string loopText: root.preview ? "all"
        : ServiceMusic.loopState === 2 ? "all" : ServiceMusic.loopState === 1 ? "one" : "off"

    MusicNow { id: m; preview: root.preview }

    HoverHandler {
        id: hover
        enabled: !root.preview
        onHoveredChanged: {
            GlobalStates.widgetTextFocus = hovered
            if (hovered)
                keys.forceActiveFocus()
        }
    }

    Item {
        id: keys
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_Space || event.key === Qt.Key_K) m.toggle()
            else if (event.key === Qt.Key_H || event.key === Qt.Key_Left) m.previous()
            else if (event.key === Qt.Key_L || event.key === Qt.Key_Right) m.next()
            else if (event.key === Qt.Key_S) m.toggleShuffle()
            else return
            event.accepted = true
        }
    }

    component Key: Rectangle {
        id: k
        property string key: ""
        property string label: ""
        property bool accent: false
        signal clicked()
        width: row.implicitWidth + 18
        height: 28
        radius: 6
        color: k.accent ? Colors.primary : area.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
        Row {
            id: row
            anchors.centerIn: parent
            spacing: 6
            CustomText { content: k.key; size: 12; weight: 700; family: "JetBrains Mono"; customColor: k.accent ? Colors.primaryText : Colors.primary }
            CustomText { content: k.label; size: 12; family: "JetBrains Mono"; customColor: k.accent ? Colors.primaryText : Colors.surfaceVariantText }
        }
        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: k.clicked()
        }
    }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(420, 200)

        Rectangle {
            anchors.fill: parent
            radius: 18
            color: Colors.surfaceContainerLowest
            border.width: 1
            border.color: hover.hovered ? Colors.primaryContainer : Colors.surfaceContainer

            Column {
                anchors.fill: parent
                anchors.margins: 16
                anchors.leftMargin: 18
                spacing: root.compact ? 2 : 5

                Item {
                    width: parent.width
                    height: 14
                    CustomText { content: "~/music"; size: 11; family: root.mono; customColor: Colors.outlineVariant }
                    CustomText { anchors.right: parent.right; content: "mpris · " + (m.source !== "" ? m.source.toLowerCase() : "none"); size: 11; family: root.mono; customColor: Colors.outlineVariant }
                }
                Row {
                    spacing: 8
                    CustomText { content: "❯"; size: root.fs; family: root.mono; customColor: Colors.tertiary }
                    CustomText { content: "nowplaying"; size: root.fs; family: root.mono }
                }
                CustomText { x: 16; width: parent.width - 16; content: m.title; size: root.fs; weight: 700; family: root.mono; customColor: Colors.primary }
                CustomText { x: 16; width: parent.width - 16; content: [m.artist, m.albumShown].filter(s => s !== "").join(" — "); size: root.fs; family: root.mono; customColor: Colors.outline }
                Row {
                    x: 16
                    spacing: 0
                    CustomText { content: "█".repeat(root.litCells); size: root.fs; family: root.mono; customColor: Colors.primary }
                    CustomText { content: "░".repeat(root.barCells - root.litCells); size: root.fs; family: root.mono; customColor: Colors.surfaceContainerHighest }
                    CustomText { content: " " + m.elapsedText; size: root.fs; family: root.mono }
                    CustomText { content: "/" + m.lengthText; size: root.fs; family: root.mono; customColor: Colors.outlineVariant }
                }
                Row {
                    x: 16
                    spacing: 0
                    CustomText { content: "vol "; size: root.fs; family: root.mono; customColor: Colors.outline }
                    CustomText { content: "▮".repeat(root.volLit); size: root.fs; family: root.mono; customColor: Colors.secondary }
                    CustomText { content: "▮".repeat(10 - root.volLit); size: root.fs; family: root.mono; customColor: Colors.surfaceContainerHighest }
                    CustomText { content: " " + Math.round(root.volume * 100) + "%   shuffle "; size: root.fs; family: root.mono; customColor: Colors.outline }
                    CustomText { content: m.shuffle ? "on" : "off"; size: root.fs; family: root.mono; customColor: m.shuffle ? Colors.tertiary : Colors.error }
                    CustomText { content: "   repeat "; size: root.fs; family: root.mono; customColor: Colors.outline }
                    CustomText { content: root.loopText; size: root.fs; family: root.mono; customColor: Colors.tertiary }
                }
                Item { width: 1; height: 4 }
                Row {
                    x: 16
                    spacing: 8
                    Key { key: "h"; label: "prev"; onClicked: m.previous() }
                    Key { key: "space"; label: m.playing ? "pause" : "play"; accent: true; onClicked: m.toggle() }
                    Key { key: "l"; label: "next"; onClicked: m.next() }
                    Key { key: "s"; label: "shuffle"; onClicked: m.toggleShuffle() }
                }
            }

            Row {
                visible: !root.compact
                anchors.left: parent.left
                anchors.leftMargin: 18
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 14
                spacing: 8
                CustomText { content: "❯"; size: root.fs; family: root.mono; customColor: Colors.tertiary }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 9
                    height: 16
                    color: Colors.surfaceText
                    SequentialAnimation on opacity {
                        running: hover.hovered
                        loops: Animation.Infinite
                        NumberAnimation { to: 0; duration: 1 }
                        PauseAnimation { duration: 530 }
                        NumberAnimation { to: 1; duration: 1 }
                        PauseAnimation { duration: 530 }
                    }
                }
            }
        }
    }
}
