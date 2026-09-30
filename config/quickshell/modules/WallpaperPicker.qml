import QtQuick
import "../services"

Rectangle {
    width: 640
    height: 380
    radius: 16
    color: Colors.background

    GridView {
        anchors.fill: parent
        anchors.margins: 14
        cellWidth: 148
        cellHeight: 96
        clip: true
        model: Wallpapers.files

        delegate: Rectangle {
            width: 136
            height: 84
            radius: 10
            color: "#1a1a1a"
            clip: true
            border.width: modelData === Wallpapers.selected ? 2 : 0
            border.color: Colors.accent

            Image {
                anchors.fill: parent
                source: "file://" + modelData
                fillMode: Image.PreserveAspectCrop
                asynchronous: true   // keeps the grid from freezing while loading
            }

            MouseArea {
                anchors.fill: parent
                onClicked: Wallpapers.setWallpaper(modelData)
            }
        }
    }
}