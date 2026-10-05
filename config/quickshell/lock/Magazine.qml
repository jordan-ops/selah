import QtQuick
import "../services" as Services

// Style "magazine" — typography-forward and deliberately off-centre:
// everything sits bottom-left as one block, the clock set huge like a
// headline with the date as its dateline, the prompt directly beneath.
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
        anchors.left: parent.left
        anchors.leftMargin: 64
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 56
        width: 560
        spacing: 8

        Text {
            font.family: Services.Fonts.family
            text: style.lock ? Qt.formatDateTime(style.lock.now, "dddd, MMMM d").toUpperCase() : ""
            font.pixelSize: 16
            font.letterSpacing: 3
            color: Services.Colors.textMuted
        }

        Text {
            font.family: Services.Fonts.family
            text: Services.Time.time
            font.pixelSize: 190
            font.weight: Font.Bold
            color: Services.Colors.text
        }

        Item { width: 1; height: 12 }   // spacer

        Text {
            font.family: Services.Fonts.family
            text: style.lock ? style.lock.userName : ""
            font.pixelSize: 14
            color: Services.Colors.textMuted
        }

        AuthField {
            id: field
            lock: style.lock
            interactive: style.interactive
            fieldWidth: 520
        }

        AuthStatus {
            lock: style.lock
            statusWidth: 520
        }
    }
}
