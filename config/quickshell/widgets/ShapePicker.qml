// Ported from Nebula's customComponents/ShapePicker.qml (GPL-3.0) — qs.modules
// imports dropped (kit now lives beside its users in widgets/).
import QtQuick
import QtQuick.Layouts

import "shapes/" as MaterialShapes
import "shapes/shape-library.js" as ShapeLibrary

ColumnLayout {
    id: root

    property string selected: ""
    property string autoHint: ""
    property bool showAuto: true
    property string autoLabel: "Auto"
    property string autoIcon: "autorenew"
    property string pickedHint: "Locked to this shape"
    signal picked(string name)

    spacing: 10

    RowLayout {
        Layout.fillWidth: true
        visible: root.showAuto
        spacing: 10

        Rectangle {
            readonly property bool active: root.selected === ""
            implicitWidth: autoRow.implicitWidth + 26
            implicitHeight: 32
            radius: 16
            color: active ? Colors.primary
                 : autoMouse.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
            Behavior on color { EffectsColorAnim {} }

            RowLayout {
                id: autoRow
                anchors.centerIn: parent
                spacing: 6

                MaterialIconSymbol {
                    content: root.autoIcon
                    iconSize: 15
                    customColor: parent.parent.active ? Colors.primaryText : Colors.surfaceText
                }
                CustomText {
                    content: root.autoLabel
                    size: 12
                    weight: 600
                    customColor: parent.parent.active ? Colors.primaryText : Colors.surfaceText
                }
            }

            MouseArea {
                id: autoMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.picked("")
            }
        }

        CustomText {
            Layout.fillWidth: true
            content: root.selected === "" ? root.autoHint : root.pickedHint
            size: 11
            customColor: Colors.outline
            elide: Text.ElideRight
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 8
        rowSpacing: 5
        columnSpacing: 5

        Repeater {
            model: ShapeLibrary.names

            delegate: Rectangle {
                id: cell
                required property string modelData
                readonly property bool active: root.selected === cell.modelData

                implicitWidth: 34
                implicitHeight: 34
                radius: 10
                color: cell.active ? Colors.primaryContainer
                     : cellMouse.containsMouse ? Colors.surfaceContainerHighest : Colors.surfaceContainerHigh
                border.width: cell.active ? 2 : 0
                border.color: Colors.primary
                Behavior on color { EffectsColorAnim {} }

                MaterialShapes.ShapeCanvas {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    roundedPolygon: ShapeLibrary.get(cell.modelData)
                    color: cell.active ? Colors.primary : Qt.alpha(Colors.surfaceText, 0.75)
                }

                MouseArea {
                    id: cellMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(cell.modelData)
                }
            }
        }
    }
}
