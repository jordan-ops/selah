import QtQuick
import "../services"

Text{
    font.family: Fonts.family
    anchors.verticalCenter: parent.verticalCenter
    color: Colors.text
    font.pixelSize: Theme.fontSize
    font.bold: Theme.fontBold
    text: Time.time

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: ClockCard.toggle()
    }
}
