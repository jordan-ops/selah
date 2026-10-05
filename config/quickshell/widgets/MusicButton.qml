// Ported from Nebula's Widgets/MusicButton.qml (GPL-3.0) — qs.modules imports
// dropped (everything it used is a sibling in widgets/ now).
import QtQuick

Rectangle {
    id: root

    property string icon: ""
    property string label: ""
    property real iconSize: 20
    property string family: SettingsConfig.general.defaultFont ?? "Rubik"
    property real labelSize: 12
    property color fg: Colors.surfaceText
    property color bg: "transparent"
    property color hoverBg: Qt.alpha(root.fg, 0.12)
    property bool filled: false
    readonly property bool hovered: area.containsMouse

    signal clicked()

    implicitWidth: 40
    implicitHeight: 40
    radius: height / 2
    color: area.containsMouse && root.hoverBg.a > 0 && root.bg.a === 0 ? root.hoverBg : root.bg


    Row {
        anchors.centerIn: parent
        spacing: 6

        MaterialIconSymbol {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            content: root.icon
            iconSize: area.pressed ? root.iconSize * 0.88 : root.iconSize
            Behavior on iconSize { SpatialAnim { speed: "fast" } }
            fill: root.filled ? 1 : 0
            customColor: root.fg
        }

        CustomText {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            content: root.label
            family: root.family
            size: root.labelSize
            weight: 700
            customColor: root.fg
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked()
    }
}
