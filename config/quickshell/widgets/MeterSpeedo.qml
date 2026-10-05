// Ported from Nebula's customComponents/MeterSpeedo.qml (GPL-3.0) — qs.modules
// imports dropped (kit now lives beside its users in widgets/).
import QtQuick
import QtQuick.Shapes

Item {
    id: root

    property real value: 0
    property real warnAt: 0.8
    property real thickness: Math.max(3, root.width * 0.1)
    property bool showTicks: true
    property color color: Colors.primary
    property color trackColor: Colors.surfaceContainerHighest
    property color warnColor: Colors.error
    property color needleColor: Colors.surfaceText
    property color hubHole: Colors.surfaceContainerHigh

    readonly property real r: root.width / 2 - root.thickness / 2
    readonly property real cx: root.width / 2
    readonly property real cy: root.thickness / 2 + root.r
    readonly property real hub: Math.max(3, root.width * 0.06)
    property real shown: Math.max(0, Math.min(1, root.value))

    Behavior on shown { SpatialAnim {} }

    implicitHeight: root.cy + root.hub

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.trackColor
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r; radiusY: root.r; startAngle: 180; sweepAngle: 180 }
        }

        ShapePath {
            strokeColor: root.shown > 0.004 ? root.color : "transparent"
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r; radiusY: root.r; startAngle: 180; sweepAngle: Math.max(0.1, 180 * root.shown) }
        }

        ShapePath {
            strokeColor: root.showTicks ? root.warnColor : "transparent"
            strokeWidth: Math.max(1, root.thickness * 0.16)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc { centerX: root.cx; centerY: root.cy; radiusX: root.r - root.thickness * 1.05; radiusY: root.r - root.thickness * 1.05; startAngle: 180 + 180 * root.warnAt; sweepAngle: 180 * (1 - root.warnAt) }
        }
    }

    Repeater {
        model: root.showTicks ? 9 : 0

        delegate: Item {
            required property int index
            x: root.cx - width / 2
            y: root.cy - height / 2
            width: 2 * (root.r - root.thickness * 1.05)
            height: width
            rotation: -90 + 180 * index / 8

            Rectangle {
                x: (parent.width - width) / 2
                y: -height / 2
                width: Math.max(1, root.thickness * 0.14)
                height: width
                radius: width / 2
                color: Colors.outlineVariant
            }
        }
    }

    Rectangle {
        id: needle
        x: root.cx - width / 2
        y: root.cy - height
        width: Math.max(2, root.thickness * 0.32)
        height: root.r - root.thickness * 0.6
        radius: width / 2
        antialiasing: true
        color: root.needleColor
        transformOrigin: Item.Bottom
        rotation: -90 + 180 * root.shown
    }

    Rectangle {
        x: root.cx - width / 2
        y: root.cy - height / 2
        width: root.hub * 2
        height: width
        radius: width / 2
        color: root.needleColor

        Rectangle {
            anchors.centerIn: parent
            width: parent.width * 0.4
            height: width
            radius: width / 2
            color: root.hubHole
        }
    }
}
