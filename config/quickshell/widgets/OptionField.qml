// Ported from Nebula's Widgets/OptionField.qml (GPL-3.0) — qs.modules imports
// dropped (everything it used is a sibling in widgets/ now).
import QtQuick

Rectangle {
    id: optionField

    property alias text: fieldInput.text
    property string placeholder: ""
    signal committed(string value)

    implicitWidth: 140
    implicitHeight: 34
    radius: 10
    color: Colors.surfaceContainerHighest
    border.width: fieldInput.activeFocus ? 2 : 0
    border.color: Colors.primary

    TextInput {
        id: fieldInput
        anchors.fill: parent
        anchors.leftMargin: 10
        anchors.rightMargin: 10
        color: Colors.inverseSurface
        font.pixelSize: 13
        clip: true
        verticalAlignment: TextInput.AlignVCenter
        onEditingFinished: optionField.committed(text.trim())
    }

    CustomText {
        anchors.left: parent.left
        anchors.leftMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        visible: fieldInput.text.length === 0 && !fieldInput.activeFocus
        content: optionField.placeholder
        size: 12
        customColor: Colors.outline
    }
}
