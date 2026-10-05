// Ported from Nebula's Widgets/WidgetDesignStage.qml (GPL-3.0) — verbatim.
import QtQuick

Item {
    id: root

    property size design: Qt.size(530, 310)
    default property alias content: stage.data

    readonly property real k: 1
    readonly property real stageWidth: stage.width
    readonly property real stageHeight: stage.height

    Item {
        id: stage
        width: root.k > 0 ? root.width / root.k : root.design.width
        height: root.k > 0 ? root.height / root.k : root.design.height
        scale: root.k
        transformOrigin: Item.TopLeft
    }
}
