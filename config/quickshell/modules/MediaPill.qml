import QtQuick
import Quickshell
import Quickshell.Widgets
import "../services"

Rectangle {
    id: mediaPill
    width: 90
    height: 34
    radius: height / 2
    color: Colors.background

    property bool expanded: false

    Connections{
        target: Media
        function onHasPlayerChanged(){
            if (!Media.hasPlayer) mediaPill.expanded = false
        }
    }

    // scale + opacity driven by whether a player exists at all (playing OR paused);
    // only a fully closed app (no player) hides the pill
    scale: Media.hasPlayer ? 1 : 0.8
    opacity: Media.hasPlayer ? 1 : 0
    visible: opacity > 0   // fully removes it from hit-testing when hidden

    Behavior on opacity { NumberAnimation { duration: Services.Motion.medium2; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }
    Behavior on scale { SpringAnimation { spring: Services.Motion.spatialFastSpring; damping: Services.Motion.spatialFastDamping } }

    Row{
        anchors.centerIn:parent
        spacing:6

        Text{color:Colors.accent
            font.family: Fonts.family
            font.pixelSize: Theme.fontSize
            font.bold: Theme.fontBold
            text: Media.appIcon
        }
    

    
    Text {
        font.family: Fonts.family
        visible: !Media.playing   // hasPlayer but not playing = paused
        color: Colors.text
        font.pixelSize: Theme.fontSize
        anchors.verticalCenter: parent.verticalCenter
        text: "󰏤"
    }
    Text {
        font.family: Fonts.family
        color: Colors.text
        font.pixelSize: Theme.fontSize
        font.bold: Theme.fontBold
        anchors.verticalCenter: parent.verticalCenter
        text: Media.formatTime(Media.position)
    }
    }
    MouseArea{
        anchors.fill:parent
        onClicked: mediaPill.expanded = !mediaPill.expanded
    }

}
