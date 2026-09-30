import Quickshell
import Quickshell.Io
import QtQuick
import "./services" as Services

Item {
    id: root
    implicitWidth: 900
    implicitHeight: 220

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Services.Colors.background

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Text {
                font.family: Services.Fonts.family
                text: Services.Themes.currentTheme !== ""
                    ? "Wallpapers — " + Services.Themes.currentTheme
                    : "Wallpapers"
                color: Services.Colors.text
                font.pixelSize: 14
                font.bold: true
            }

            Text {
                font.family: Services.Fonts.family
                visible: Services.Wallpapers.wallpapers.length === 0
                text: Services.Themes.currentTheme === ""
                    ? "No theme active yet"
                    : "No wallpapers found in this theme's wallpapers/ folder"
                color: Services.Colors.text_muted
                font.pixelSize: 12
            }

            // Single horizontal row, scrolls sideways if there are more
            // than fit — same idea as the commented-out horizontal variant
            // already sitting at the bottom of ThemePicker.qml, just
            // applied here instead of the grid version.
            ListView {
                id: wallList
                width: parent.width
                height: parent.height - 34
                orientation: ListView.Horizontal
                clip: true
                spacing: 12
                model: Services.Wallpapers.wallpapers
                currentIndex: Services.Wallpapers.selectedIndex
                focus: true

                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        Services.Wallpapers.closePicker()
                        event.accepted = true
                    } else if (event.key === Qt.Key_Right) {
                        Services.Wallpapers.moveSelection(1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Left) {
                        Services.Wallpapers.moveSelection(-1)
                        event.accepted = true
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        Services.Wallpapers.applySelected()
                        event.accepted = true
                    }
                }

                delegate: Item {
                    width: 220
                    height: wallList.height

                    Rectangle {
                        anchors.centerIn: parent
                        width: 200
                        height: parent.height - 8
                        radius: 8
                        color: Services.Colors.surface
                        clip: true

                        border.width: index === Services.Wallpapers.selectedIndex ? 2 : 0
                        border.color: Services.Colors.accent

                        Image {
                            anchors.fill: parent
                            source: "file://" + modelData
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Services.Wallpapers.selectedIndex = index
                                Services.Wallpapers.apply(modelData)
                            }
                        }
                    }
                }

                // keeps the selected thumbnail scrolled into view as you arrow left/right
                Connections {
                    target: Services.Wallpapers
                    function onSelectedIndexChanged() {
                        wallList.positionViewAtIndex(Services.Wallpapers.selectedIndex, ListView.Contain)
                    }
                    function onOpenChanged() {
                        if (Services.Wallpapers.open) wallList.forceActiveFocus()
                    }
                }
            }
        }
    }
}
