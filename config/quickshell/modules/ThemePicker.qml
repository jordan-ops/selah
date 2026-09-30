import Quickshell
import Quickshell.Io
import QtQuick
import "../services" as Services

Item {
    id: root
    implicitWidth: 600
    implicitHeight: 520

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: Services.Colors.background

        GridView {
            id: themeGrid
            anchors.fill: parent
            anchors.margins: 16
            clip: true
            cellWidth: width / 2
            cellHeight: 110
            model: Services.Themes.themes
            currentIndex: Services.Themes.selectedIndex
            focus: true

            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape) {
                    Services.Themes.closePicker()
                    event.accepted = true
                } else if (event.key === Qt.Key_Right) {
                    Services.Themes.moveSelection(1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Left) {
                    Services.Themes.moveSelection(-1)
                    event.accepted = true
                } else if (event.key === Qt.Key_Down) {
                    Services.Themes.moveSelection(2)
                    event.accepted = true
                } else if (event.key === Qt.Key_Up) {
                    Services.Themes.moveSelection(-2)
                    event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                    Services.Themes.applySelected()
                    event.accepted = true
                }
            }

            delegate: Item {
                width: themeGrid.cellWidth
                height: themeGrid.cellHeight

                Column {
                    anchors.centerIn: parent
                    spacing: 8

                    Rectangle {
                        id: swatch
                        width: 380
                        height: 180
                        radius: 2
                        anchors.horizontalCenter: parent.horizontalCenter

                        property var themeData: ({})
                        color: (themeData.md3 && themeData.md3.primary) || "#888888"

                        border.width: index === Services.Themes.selectedIndex ? 2 : 0
                        border.color: Services.Colors.accent

                        FileView {
                            path: Quickshell.env("HOME") + "/.config/themes/" + modelData + "/quickshell/colors.json"
                            onLoaded: {
                                try {
                                    swatch.themeData = JSON.parse(text())
                                } catch (e) {
                                    console.log("ThemePicker: failed to parse", modelData, e)
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Services.Themes.selectedIndex = index
                                Services.Themes.apply(modelData)
                            }
                        }
                    }

                    Text {
                        font.family: Services.Fonts.family
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: modelData
                        color: Services.Colors.text
                        font.pixelSize: 12
                    }
                }
            }

            // keeps the selected swatch scrolled into view as you arrow through rows
            Connections {
                target: Services.Themes
                function onSelectedIndexChanged() {
                    themeGrid.positionViewAtIndex(Services.Themes.selectedIndex, GridView.Contain)
                }
                function onOpenChanged() {
                    if (Services.Themes.open) themeGrid.forceActiveFocus()
                }
            }
        }
    }
}


// import Quickshell
// import Quickshell.Io
// import QtQuick
// import "../services" as Services
//
// Item {
//     id: root
//     implicitWidth: 420
//     implicitHeight: 140
//
//     Rectangle {
//         anchors.fill: parent
//         radius: 16
//         color: Services.Colors.background
//
//         ListView {
//             id: themeList
//             anchors.fill: parent
//             anchors.margins: 16
//             orientation: ListView.Horizontal
//             spacing: 16
//             model: Services.Themes.themes
//
//             delegate: Column {
//                 spacing: 8
//                 width: 80
//
//                 Rectangle {
//                     id: swatch
//                     width: 90
//                     height: 56
//                     radius: 8
//                     anchors.horizontalCenter: parent.horizontalCenter
//
//                     // this theme's OWN colors.json, read just for its primary swatch —
//                     // separate from Services.Colors, which only reflects whichever
//                     // theme is currently ACTIVE, not every theme in the list
//                     property var themeData: ({})
//                     color: (themeData.md3 && themeData.md3.primary) || "#888888"
//
//                     border.width: modelData === Services.Themes.currentTheme ? 2 : 0
//                     border.color: Services.Colors.accent
//
//                     FileView {
//                         path: Quickshell.env("HOME") + "/.config/theme/" + modelData + "/quickshell/colors.json"
//                         onLoaded: {
//                             try {
//                                 swatch.themeData = JSON.parse(text())
//                             } catch (e) {
//                                 console.log("ThemePicker: failed to parse", modelData, e)
//                             }
//                         }
//                     }
//
//                     MouseArea {
//                         anchors.fill: parent
//                         onClicked: Services.Themes.apply(modelData)
//                     }
//                 }
//
//                 Text {
//                     anchors.horizontalCenter: parent.horizontalCenter
//                     text: modelData
//                     color: Services.Colors.text
//                     font.pixelSize: 12
//                 }
//             }
//         }
//     }
// }
