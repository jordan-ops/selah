import QtQuick
import "../services" as Services

// A clickable toggle "chip" — icon on top, label under it.
// Waybar analogy: this is one Waybar module (e.g. "custom/bluetooth")
// that swaps its own background color when its "active" class is set.
// We just pass in icon/label/active from outside and emit clicked().
Rectangle {
    id: root

    property string icon: "?"
    property string label: ""
    property bool active: false
    signal clicked()

    width: 100
    height: 64
    radius: 14
    color: active ? Services.Colors.accent : Services.Colors.surface

    Behavior on color { ColorAnimation { duration: Services.Motion.short2; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.standardCurve } }

    Column {
        anchors.centerIn: parent
        spacing: 4

        Text {
            font.family: Services.Fonts.family
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.icon
            font.pixelSize: 18
            color: root.active ? Services.Colors.background : Services.Colors.text
        }

        Text {
            font.family: Services.Fonts.family
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.label
            font.pixelSize: 11
            color: root.active ? Services.Colors.background : Services.Colors.text_muted
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: root.clicked()
    }
}
