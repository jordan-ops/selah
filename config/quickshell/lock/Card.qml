import QtQuick
import "../services" as Services

// Style "card" — the prompt boxed into one frosted panel in the middle
// of the screen: clock and date, an avatar disc carrying the initial,
// then the field. The panel fill is Colors.panel (the themed background
// at the "Panel transparency" alpha), so the blurred wallpaper reads
// through it — glass, not a sticker.
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

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 560
        // sized off the column, which centers itself inside the card —
        // no loop: the column's height comes from its children alone
        height: content.height + 76
        radius: 26
        color: Services.Colors.panel
        border.width: 1
        border.color: Services.Colors.low

        Column {
            id: content
            anchors.centerIn: parent
            width: 460
            spacing: 12

            Text {
                font.family: Services.Fonts.family
                anchors.horizontalCenter: parent.horizontalCenter
                text: Services.Time.time
                font.pixelSize: 64
                font.weight: Font.Bold
                color: Services.Colors.text
            }

            Text {
                font.family: Services.Fonts.family
                anchors.horizontalCenter: parent.horizontalCenter
                text: style.lock ? Qt.formatDateTime(style.lock.now, "dddd, MMMM d") : ""
                font.pixelSize: 14
                color: Services.Colors.textMuted
            }

            Item { width: 1; height: 14 }   // spacer

            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: 64
                height: 64
                radius: 32
                color: Services.Colors.accent

                Text {
                    anchors.centerIn: parent
                    font.family: Services.Fonts.family
                    text: style.lock && style.lock.userName
                        ? style.lock.userName.charAt(0).toUpperCase() : "?"
                    font.pixelSize: 26
                    font.weight: Font.Bold
                    color: Services.Colors.background
                }
            }

            Text {
                font.family: Services.Fonts.family
                anchors.horizontalCenter: parent.horizontalCenter
                text: style.lock ? style.lock.userName : ""
                font.pixelSize: 14
                font.weight: Font.Bold
                color: Services.Colors.text
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
}
