// Ported from Nebula's Widgets/HiResShape.qml (GPL-3.0) — qs.modules imports
// dropped (everything it used is a sibling in widgets/ now).
import QtQuick
import "shapes/" as MaterialShapes

Item {
    id: root

    property var polygon: null
    property color color: "white"
    property real k: 1
    readonly property real res: Math.max(1, root.k)

    MaterialShapes.ShapeCanvas {
        width: root.width * root.res
        height: root.height * root.res
        scale: 1 / root.res
        transformOrigin: Item.TopLeft
        roundedPolygon: root.polygon
        color: root.color
    }
}
