// Ported from Nebula's Widgets/SysCellsWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "sysCells"
    tile: Qt.size(WidgetSizes.span(2), WidgetSizes.span(2))
    resizable: true
    readonly property real sw: designStage.stageWidth
    readonly property real sh: designStage.stageHeight
    minSpan: Qt.size(2, 2)
    maxSpan: Qt.size(3, 3)
    backdropRadius: WidgetSizes.radius * designStage.k
    defaultPos: Qt.point(585, 165)

    readonly property var si: root.preview ? PreviewData : ServiceSystemInfo
    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property real used: root.si.diskUsage
    readonly property bool full: root.used >= 0.8
    readonly property int lit: Math.round(root.used * 10)
    readonly property color tint: root.full ? Colors.error : Colors.primary

    Component.onCompleted: root.si.retain()
    Component.onDestruction: root.si.release()

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(200, 200)

        WidgetCard {
            anchors.fill: parent

            CustomText {
                x: parent.pad; y: parent.pad
                content: "DISK · /"
                size: 11
                weight: 700
                font.letterSpacing: 1.3
                customColor: Colors.outline
            }
            CustomText {
                anchors.right: parent.right
                anchors.rightMargin: parent.pad
                y: parent.pad
                content: Math.round(root.used * 100) + "%"
                size: 11
                weight: 700
                customColor: root.tint
            }

            Column {
                id: battery
                x: parent.pad
                y: parent.pad + 26
                width: 70
                height: parent.height - y - parent.pad
                spacing: 3

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 28
                    height: 7
                    topLeftRadius: 3
                    topRightRadius: 3
                    color: Colors.outlineVariant
                }
                Rectangle {
                    width: parent.width
                    height: parent.height - 10
                    radius: 12
                    color: "transparent"
                    border.width: 2
                    border.color: Colors.outline

                    Column {
                        anchors.fill: parent
                        anchors.margins: 5
                        spacing: 3
                        Repeater {
                            model: 10
                            delegate: Rectangle {
                                required property int index
                                width: parent.width
                                height: (parent.height - 27) / 10
                                radius: 4
                                color: 9 - index < root.lit ? root.tint : Colors.surfaceContainerHigh
                                Behavior on color { EffectsColorAnim {} }
                            }
                        }
                    }
                }
            }

            Column {
                anchors.left: battery.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.rightMargin: parent.pad - 4
                anchors.bottom: parent.bottom
                anchors.bottomMargin: parent.pad
                spacing: 8

                Column {
                    CustomText {
                        content: Math.round(root.si.diskTotalGb - root.si.diskUsedGb) + " GB"
                        family: root.display
                        renderType: Text.QtRendering
                        size: 24
                        weight: 400
                        customColor: root.tint
                    }
                    CustomText { content: "free left"; size: 11; customColor: Colors.surfaceVariantText }
                }
                Column {
                    CustomText { content: Math.round(root.si.diskUsedGb) + " / " + Math.round(root.si.diskTotalGb); size: 14; weight: 700 }
                    CustomText { content: "GB used"; size: 11; customColor: Colors.surfaceVariantText }
                }
                Rectangle {
                    visible: root.full
                    width: cleanText.implicitWidth + 16
                    height: 26
                    radius: 8
                    color: Colors.errorContainer
                    CustomText {
                        id: cleanText
                        anchors.centerIn: parent
                        content: "Clean up"
                        size: 11
                        weight: 700
                        customColor: Colors.errorContainerText
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (root.preview)
                                return
                            GlobalStates.settingsPage = 11
                            GlobalStates.settingsOpen = true
                        }
                    }
                }
            }
        }
    }
}
