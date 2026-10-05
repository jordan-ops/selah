// Ported from Nebula's Widgets/DateWidgetAccent.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import Quickshell
import QtQuick
import QtQuick.Layouts

WidgetHost {
    id: root
    configKey: "dateWidget"
    defaultPos: Qt.point(300, 300)
    tile: Qt.size(WidgetSizes.span(2), WidgetSizes.span(1))

    // Left accent bar — only visual element besides text
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: 4
        radius: 2
        color: Colors.primary
    }

    ColumnLayout {
        anchors.left: parent.left
        anchors.leftMargin: 18
        anchors.verticalCenter: parent.verticalCenter
        spacing: 0

        // Day name
        CustomText {
            content: ServiceClock.day.toUpperCase()
            size: 10
            weight: 700
            customColor: Colors.outline
            font.letterSpacing: 3
        }

        // Date + month/year side by side
        RowLayout {
            spacing: 10
            Layout.topMargin: -2

            CustomText {
                content: ServiceClock.date
                size: 64
                weight: 700
                customColor: Colors.primary
                font.family: SettingsConfig.general.displayFont ?? "Titan One"
                style: Text.Raised
                styleColor: Qt.alpha(Colors.primary, 0.2)
            }

            ColumnLayout {
                spacing: 1
                Layout.alignment: Qt.AlignBottom
                Layout.bottomMargin: 10

                CustomText {
                    content: ServiceClock.month
                    size: 14
                    weight: 600
                    customColor: Colors.surfaceText
                }

                CustomText {
                    content: ServiceClock.year
                    size: 11
                    weight: 400
                    customColor: Colors.outline
                }
            }
        }
    }
}
