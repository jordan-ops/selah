import QtQuick
import "shapes"
import "shapes/material-shapes.js" as MaterialShapeFn

// Ported from Nebula's Widgets/ShapeWidget.qml (GPL-3.0) — a WidgetHost
// whose face is a Material shape (shape-geom.js renders it), and whose
// white copy doubles as a ShaderEffectSource mask for clipped content.
// Module imports dropped; the shapes/ directory and its name-getter JS
// are explicit imports because they live in a subdirectory, not beside
// this file.
WidgetHost {
    id: root

    property var shape: MaterialShapeFn.getCircle()
    property color faceColor: WidgetSizes.cardColor
    property bool showFace: true
    property real faceRotation: 0
    readonly property real faceSize: Math.min(width, height)
    readonly property Item shapeTexture: shapeMask

    backdropMask: shapeMask

    ShapeCanvas {
        z: -2
        visible: root.showFace
        anchors.centerIn: parent
        width: root.faceSize
        height: root.faceSize
        rotation: root.faceRotation
        roundedPolygon: root.shape
        color: root.faceColor
    }

    Item {
        id: maskSource
        anchors.fill: parent

        ShapeCanvas {
            anchors.centerIn: parent
            width: root.faceSize
            height: root.faceSize
            rotation: root.faceRotation
            roundedPolygon: root.shape
            color: "white"
        }
    }

    Item {
        width: 0
        height: 0
        clip: true

        ShaderEffectSource {
            id: shapeMask
            width: root.width
            height: root.height
            textureSize: Qt.size(root.width, root.height)
            sourceItem: maskSource
            hideSource: true
            live: true
        }
    }
}
