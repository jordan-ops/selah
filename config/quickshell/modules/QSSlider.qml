import QtQuick
import "../services" as Services

// A draggable 0..1 slider. Visually it's the exact same idea as the
// osdContent progress bar already in Bar.qml — a background Rectangle
// with a colored Rectangle inside it whose width equals value * track width.
// We've just added a MouseArea so you can drag it, since this one is
// meant to be interacted with rather than just displayed.
Item {
    id: root

    property string icon: "?"
    property real value: 0   // 0..1
    signal moved(real value)

    height: 36

    Row {
        anchors.fill: parent
        spacing: 10

        Text {
            font.family: Services.Fonts.family
            text: root.icon
            font.pixelSize: 16
            color: Services.Colors.text
            anchors.verticalCenter: parent.verticalCenter
        }

        Rectangle {
            id: track
            width: parent.width - 30
            height: 8
            radius: 4
            anchors.verticalCenter: parent.verticalCenter
            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.15)

            Rectangle {
                width: track.width * root.value
                height: parent.height
                radius: 4
                color: Services.Colors.accent
                Behavior on width { SpringAnimation { spring: Services.Motion.bounceSpring; damping: Services.Motion.bounceDamping } }
            }

            MouseArea {
                id: dragArea
                anchors.fill: parent
                onPressed: mouse => updateValue(mouse.x)
                onPositionChanged: mouse => { if (pressed) updateValue(mouse.x) }

                function updateValue(x) {
                    let v = Math.max(0, Math.min(1, x / track.width))
                    root.value = v
                    root.moved(v)
                }
            }
        }
    }
}
