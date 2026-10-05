import QtQuick
import "../services" as Services

// Style "classic" — the original lock layout, unchanged: one centered
// column, the clock oversized on top, date under it, then the prompt.
Item {
    id: style
    anchors.fill: parent

    property var lock: null
    property bool interactive: true

    function focusField() { field.forceFocus() }

    LockBackdrop {
        lock: style.lock
        interactive: style.interactive
    }

    Column {
        anchors.centerIn: parent
        width: 460
        spacing: 10

        Text {
            font.family: Services.Fonts.family
            anchors.horizontalCenter: parent.horizontalCenter
            text: Services.Time.time
            font.pixelSize: 150
            font.weight: Font.Bold
            color: Services.Colors.text
        }

        Text {
            font.family: Services.Fonts.family
            anchors.horizontalCenter: parent.horizontalCenter
            text: style.lock ? Qt.formatDateTime(style.lock.now, "dddd, MMMM d") : ""
            font.pixelSize: 15
            color: Services.Colors.textMuted
        }

        Item { width: 1; height: 44 }   // spacer

        Text {
            font.family: Services.Fonts.family
            anchors.horizontalCenter: parent.horizontalCenter
            text: style.lock ? style.lock.userName : ""
            font.pixelSize: 13
            color: Services.Colors.textMuted
        }

        AuthField {
            id: field
            lock: style.lock
            interactive: style.interactive
            anchors.horizontalCenter: parent.horizontalCenter
        }

        AuthStatus {
            lock: style.lock
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
