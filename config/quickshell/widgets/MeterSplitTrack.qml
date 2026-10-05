// Ported from Nebula's customComponents/MeterSplitTrack.qml (GPL-3.0) — qs.modules
// imports dropped (kit now lives beside its users in widgets/).
import QtQuick

Item {
    id: root

    property real value: 0
    property real gap: Math.max(2, root.height * 0.45)
    property bool stopDot: true
    property color color: Colors.primary
    property color trackColor: Colors.secondaryContainer

    property real shown: Math.max(0, Math.min(1, root.value))

    Behavior on shown { SpatialAnim {} }

    readonly property real activeW: root.shown <= 0.001 ? 0 : Math.max(root.height, (root.width - root.gap) * root.shown)

    implicitHeight: 8

    Rectangle {
        width: root.activeW
        height: root.height
        radius: height / 2
        visible: width > 0
        color: root.color
    }

    Rectangle {
        x: root.activeW > 0 ? root.activeW + root.gap : 0
        width: Math.max(0, root.width - x)
        height: root.height
        radius: height / 2
        visible: width >= root.height
        color: root.trackColor

        Rectangle {
            visible: root.stopDot && parent.width >= root.height * 2
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: (root.height - width) / 2
            width: Math.max(2, root.height * 0.34)
            height: width
            radius: width / 2
            color: root.color
        }
    }
}
