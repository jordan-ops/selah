// Ported from Nebula's customComponents/MotionEnter.qml (GPL-3.0) — qs.modules
// imports dropped (kit now lives beside its users in widgets/).
import QtQuick

Item {
    id: root

    property real dx: 0
    property real dy: 24
    property real fromScale: 1
    property real fromRotation: 0
    property int delay: 0
    property string speed: "slow"
    property bool animated: true
    property bool exiting: false
    property real exitDx: root.dx
    property real exitDy: root.dy

    property real p: root.animated ? 0 : 1
    property bool _out: false

    implicitWidth: childrenRect.width
    implicitHeight: childrenRect.height
    opacity: Math.max(0, Math.min(1, root.p))

    transform: [
        Scale {
            origin.x: root.width / 2
            origin.y: root.height / 2
            xScale: root.fromScale + (1 - root.fromScale) * root.p
            yScale: root.fromScale + (1 - root.fromScale) * root.p
        },
        Rotation {
            origin.x: root.width / 2
            origin.y: root.height / 2
            angle: root.fromRotation * (1 - root.p)
        },
        Translate {
            x: (1 - root.p) * (root._out ? root.exitDx : root.dx)
            y: (1 - root.p) * (root._out ? root.exitDy : root.dy)
        }
    ]

    SequentialAnimation {
        running: root.animated
        PauseAnimation { duration: root.delay }
        SpatialAnim { target: root; property: "p"; from: 0; to: 1; speed: root.speed }
    }

    onExitingChanged: if (root.exiting) {
        root._out = true
        outAnim.restart()
    }

    NumberAnimation {
        id: outAnim
        target: root
        property: "p"
        to: 0
        duration: 280 + Math.min(root.delay, 400) * 0.25
        easing.type: Easing.BezierSpline
        easing.bezierCurve: [0.3, 0.0, 0.8, 0.15, 1, 1]
    }
}
