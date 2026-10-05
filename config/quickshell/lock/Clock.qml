import QtQuick
import "../services" as Services
import "../clock" as Clock

// Style "clock" — the giant time widget AS the lock. It draws in the
// box, at the size, you set by double-clicking it on the desktop: the
// same Settings.clockBox() call Background.qml makes, with room for the
// prompt reserved below it. Place it once, get it everywhere.
//
// No mouse area of its own: the lock's click layer (LockBackdrop) still
// focuses the field, and the box itself is decoration — moving it is a
// desktop job, done before you lock.
Item {
    id: style
    anchors.fill: parent

    property var lock: null
    property bool interactive: true

    function focusField() { field.forceFocus() }

    // date + user + spacer + field + status, as in Classic, plus the gap
    // above it — clockBox() clamps the box to leave exactly this much
    // below itself, so the prompt can never be pushed off-screen by a
    // widget dragged near the bottom edge.
    readonly property int authReserve: 240

    readonly property rect box:
        Services.Settings.clockBox(width, height, authReserve)

    LockBackdrop {
        lock: style.lock
        interactive: style.interactive
    }

    // the widget box — geometry straight from the shared helper, so the
    // preview card and the real lock agree with the desktop pixel for
    // pixel (the preview passes its screen-sized design canvas as parent)
    Item {
        x: style.box.x
        y: style.box.y
        width: style.box.width
        height: style.box.height

        Clock.GiantClock {
            anchors.fill: parent
            format: Services.Settings.clockFormat
            glow: Services.Settings.clockGlow
            color: Services.Colors.text
        }
    }

    // prompt block, centred under the box (clamped to stay on screen if
    // the widget sits hard against an edge)
    Column {
        width: 460
        spacing: 10
        x: Math.max(16, Math.min(style.box.x + style.box.width / 2 - 230,
                                 style.width - 460 - 16))
        y: style.box.y + style.box.height + 28

        Text {
            font.family: Services.Fonts.family
            anchors.horizontalCenter: parent.horizontalCenter
            text: style.lock
                  ? Qt.formatDateTime(style.lock.now, "dddd, MMMM d") : ""
            font.pixelSize: 15
            color: Services.Colors.textMuted
        }

        Text {
            font.family: Services.Fonts.family
            anchors.horizontalCenter: parent.horizontalCenter
            text: style.lock ? style.lock.userName : ""
            font.pixelSize: 13
            color: Services.Colors.textMuted
        }

        Item { width: 1; height: 30 }   // spacer

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
