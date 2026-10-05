import QtQuick
import "../services" as Services

// Style "minimal" — clock in the top-left corner, prompt pinned to the
// bottom edge, nothing else. The wallpaper does the talking; the only
// chrome is the field (and the status line, which stays invisible until
// authentication has something to say).
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
        anchors.leftMargin: 56
        anchors.top: parent.top
        anchors.topMargin: 48
        spacing: 6

        Text {
            font.family: Services.Fonts.family
            text: Services.Time.time
            font.pixelSize: 64
            font.weight: Font.Bold
            color: Services.Colors.text
        }

        Text {
            font.family: Services.Fonts.family
            text: style.lock ? Qt.formatDateTime(style.lock.now, "dddd, MMMM d") : ""
            font.pixelSize: 14
            color: Services.Colors.textMuted
        }
    }

    Column {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 96
        width: 420
        spacing: 10

        AuthField {
            id: field
            lock: style.lock
            interactive: style.interactive
            fieldWidth: 420
            anchors.horizontalCenter: parent.horizontalCenter
        }

        AuthStatus {
            lock: style.lock
            statusWidth: 420
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }
}
