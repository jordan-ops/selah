import QtQuick
import "../services" as Services

Text{
    font.family: Services.Fonts.family
    color: Services.Colors.text
    font.pixelSize: 14
    font.bold: true
    text: (Services.Network.isWifi ? "󰤨  " : "󰤭  ") + " "
}