import QtQuick
import "../services"

Text{
    font.family: Fonts.family
    color: Colors.text
    font.pixelSize: 14
    font.bold: Theme.fontBold
    text:(Battery.charging ? "󰂄" : "󰁹") + " "+Battery.percent +" %"
}
