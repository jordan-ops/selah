import QtQuick
import Quickshell
import "./services" as Services
import "./lock" as Lock

// `lockstyle` row — the hero of Settings ▸ Lock screen.
//
// The preview is not a mock-up: it instantiates the REAL component of
// the selected style (lock/Classic.qml and friends) into a screen-sized
// canvas and scales that down into the card, so what you see is exactly
// what the session lock will draw. Two differences from the real lock,
// both passed in here:
//   interactive: false — the preview has no password to focus and must
//                 never steal clicks from the settings window
//   a mock `lock`      — the same shape as the LockScreen root (user,
//                 date, auth state, no-op focus/submit), so every style
//                 binds the same properties it does for real
// The backdrop runs with softBlur off: a full-res blur would keep
// sampling every frame this window is open, and the sharp wallpaper
// reads fine at thumbnail size.
Item {
    id: root

    property var e: null

    // the screen the lock surface will actually cover — same size the
    // preview draws at, so proportions (150px clock on a 1080p panel,
    // say) carry over honestly
    readonly property real designW:
        Quickshell.screens.length > 0 ? Quickshell.screens[0].width : 1920
    readonly property real designH:
        Quickshell.screens.length > 0 ? Quickshell.screens[0].height : 1080

    // leave the chips their column; shrink with the window instead of
    // running under them (the panel's width is not fixed)
    readonly property real zoneW: parent ? parent.width : 750
    readonly property real thumbW: Math.max(260, Math.min(420, zoneW - 330))
    readonly property real thumbH: thumbW * designH / designW

    readonly property var mock: ({
        userName: Quickshell.env("USER") || Quickshell.env("LOGNAME") || "user",
        now: new Date(),
        lockRequested: true,
        authenticatingPassword: false,
        failureMessage: "",
        focusPassword: function () {},
        submitPassword: function () {}
    })

    readonly property var styleComponent: {
        switch (Services.Settings.lockStyle) {
        case "card":     return compCard
        case "minimal":  return compMinimal
        case "magazine": return compMagazine
        case "clock":    return compClock
        default:         return compClassic
        }
    }

    Component { id: compClassic;  Lock.Classic  { lock: root.mock; interactive: false } }
    Component { id: compCard;     Lock.Card     { lock: root.mock; interactive: false } }
    Component { id: compMinimal;  Lock.Minimal  { lock: root.mock; interactive: false } }
    Component { id: compMagazine; Lock.Magazine { lock: root.mock; interactive: false } }
    Component { id: compClock;    Lock.Clock    { lock: root.mock; interactive: false } }

    // row math, same rule as SettingsSwatchGrid: the label zone ends at
    // y=50, the card starts there, 8 px pad below → row(64 + extra) =
    // 50 + thumb + 8  =>  extra = thumb - 6
    readonly property real extraHeight: Math.max(0, thumbH - 6)

    height: 50 + thumbH + 8

    Rectangle {
        id: box
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.topMargin: 50
        width: root.thumbW
        height: root.thumbH
        radius: 12
        clip: true
        color: Services.Colors.background
        border.width: 1
        border.color: Services.Colors.low

        // screen-sized canvas, scaled into the card. transformOrigin
        // TopLeft so the whole surface lands inside the clip instead of
        // spilling past its bottom-right corner.
        Item {
            id: design
            width: root.designW
            height: root.designH
            scale: box.width / root.designW
            transformOrigin: Item.TopLeft

            Loader {
                anchors.fill: parent
                sourceComponent: root.styleComponent
            }
        }
    }

    // the chips — straight off the entry's options, writing lock.style
    // the same way the preview reads it (Services.Settings.lockStyle),
    // so highlight and preview can never disagree
    Column {
        id: chips
        anchors.left: box.right
        anchors.leftMargin: 16
        anchors.verticalCenter: box.verticalCenter
        spacing: 6

        Repeater {
            model: root.e ? (root.e.options || []) : []

            delegate: Rectangle {
                readonly property bool selected:
                    root.e.settingsKey
                    && String(modelData.value)
                       === String(Services.Settings.get(root.e.settingsKey, ""))
                height: 28
                radius: 14
                width: chipLabel.width + 26
                color: selected ? Services.Colors.accent
                    : (chipMouse.containsMouse ? Services.Colors.surfaceAlt
                                               : Services.Colors.surface)

                Behavior on color {
                    ColorAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }

                Text {
                    id: chipLabel
                    anchors.centerIn: parent
                    font.family: Services.Fonts.family
                    text: modelData.label
                    font.pixelSize: 12
                    font.bold: selected
                    color: selected ? Services.Colors.background
                                   : Services.Colors.textMuted

                    Behavior on color {
                        ColorAnimation {
                            duration: Services.Motion.effectsFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Services.Settings.set(root.e.settingsKey,
                                                     modelData.value)
                }
            }
        }
    }
}
