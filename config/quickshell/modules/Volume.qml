import QtQuick
import "../services"

Text {
    font.family: Fonts.family
    color: Colors.text
    font.pixelSize: Theme.fontSize
    font.bold: Theme.fontBold
    text: Volume.muted ? "󰝟" : (Volume.volume > 0.5 ? "󰕾" : "󰖀")

    MouseArea {
        anchors.fill: parent
        onClicked: Volume.toggleMute()   // ← exact function name TBD
    }
}
