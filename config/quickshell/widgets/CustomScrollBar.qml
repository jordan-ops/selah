// Ported from Nebula's customComponents/CustomScrollBar.qml (GPL-3.0) — module
// imports dropped (the kit now lives beside its users in widgets/) and
// answers to widgets/Colors + widgets/SettingsConfig, which speak Nebula's
// palette/config names from this shell's theme and store.
import QtQuick
import QtQuick.Controls

ScrollBar {
    id: root

    policy: ScrollBar.AsNeeded
    topPadding: 10
    bottomPadding: 10
    leftPadding: 10

    contentItem: Rectangle {
        implicitWidth: 8
        implicitHeight: root.visualSize + 50
        radius: width / 2
        color: Colors.tertiary
        
        opacity: root.policy === ScrollBar.AlwaysOn || (root.active && root.size < 1.0) ? 0.5 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: 350
                easing.type: Easing.OutQuad
            }
        }
    }
}
