import QtQuick
import "./services" as Services

Rectangle {
    id: root
    width: 280
    height: 380
    radius: 18
    color: Services.Colors.background

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Row {
            width: parent.width
            Text {
                font.family: Services.Fonts.family
                text: "Updates"
                font.pixelSize: 14
                font.bold: true
                color: Services.Colors.text
            }
            Item { width: parent.width - 190; height: 1 }
            Text {
                font.family: Services.Fonts.family
                text: "Refresh"
                font.pixelSize: 11
                color: Services.Colors.accent
                MouseArea { anchors.fill: parent; onClicked: Services.Updates.refresh() }
            }
        }

        Text {
            font.family: Services.Fonts.family
            text: Services.Updates.count + (Services.Updates.count === 1 ? " update available" : " updates available")
            font.pixelSize: 12
            color: Services.Colors.text_muted
        }

        ListView {
            width: parent.width
            height: parent.height - 110
            clip: true
            spacing: 6
            model: Services.Updates.packages

            Text {
                font.family: Services.Fonts.family
                anchors.centerIn: parent
                visible: Services.Updates.packages.length === 0
                text: "Up to date"
                font.pixelSize: 12
                color: Services.Colors.text_muted
            }

            delegate: Rectangle {
                required property var modelData
                width: parent.width
                height: 44
                radius: 8
                color: Services.Colors.surface

                Column {
                    anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                    spacing: 1
                    Row {
                        spacing: 6
                        Text { font.family: Services.Fonts.family; text: modelData.name; font.pixelSize: 12; color: Services.Colors.text }
                        Text {
                            font.family: Services.Fonts.family
                            visible: modelData.aur
                            text: "AUR"
                            font.pixelSize: 9
                            color: Services.Colors.accent
                        }
                    }
                    Text {
                        font.family: Services.Fonts.family
                        text: modelData.oldVersion + " → " + modelData.newVersion
                        font.pixelSize: 10
                        color: Services.Colors.text_muted
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 34
            radius: 17
            visible: Services.Updates.count > 0
            color: Qt.rgba(Services.Colors.accent.r, Services.Colors.accent.g, Services.Colors.accent.b, 0.18)

            Text {
                font.family: Services.Fonts.family
                anchors.centerIn: parent
                text: "Update All"
                font.pixelSize: 12
                color: Services.Colors.accent
            }
            MouseArea {
                anchors.fill: parent
                onClicked: Services.Updates.upgradeAll()
            }
        }
    }
}
