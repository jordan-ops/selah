import QtQuick
import "../services"

Text{
    font.family: Fonts.family
    color: Colors.text
    font.pixelSize: 14
    font.bold: Theme.fontBold
    // no laptop battery (VM/desktop): nothing to render
    visible: Battery.hasBattery
    text:(Battery.charging ? "󰂄" : "󰁹") + " "+Battery.percent +" %"
}
