import QtQuick
import "../services" as Services

Item {
    id: root
    width: 22
    height: 12

    property real level: Services.Battery.percent   // <-- matches your singleton
    property bool charging: Services.Battery.charging

    property color fillColor: {
        if (charging) return Services.Colors.accent
        if (level <= 15) return Services.Colors.critical
        if (level <= 30) return "#fdd663"
        return Services.Colors.text
    }

    Rectangle {
        id: body
        anchors.fill: parent
        anchors.rightMargin: 1
        radius: 4
        color: "transparent"
        border.color: Services.Colors.text
        border.width: 1.5
    }

    Rectangle {
        width: 3; height: 6; radius: 1
        color: Services.Colors.text
        anchors.left: body.right
        anchors.verticalCenter: body.verticalCenter
    }

    Rectangle {
        anchors.left: body.left
        anchors.top: body.top
        anchors.bottom: body.bottom
        anchors.margins: 2
        width: (body.width - 4) * (level / 100)
        radius: 1
        color: fillColor

        Behavior on width { SpringAnimation { spring: Services.Motion.spatialSlowSpring; damping: Services.Motion.spatialSlowDamping } }
        Behavior on color { ColorAnimation { duration: Services.Motion.medium2; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.standardCurve } }
    }
} 
