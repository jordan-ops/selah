import QtQuick
import "../services" as Services

// "Checking…" / "Authentication failed (n)" — shared by every style, so
// the wording and the fade behave identically wherever the field sits.
Text {
    id: status

    property var lock: null
    property real statusWidth: 460

    font.family: Services.Fonts.family
    width: statusWidth
    height: 18
    horizontalAlignment: Text.AlignHCenter
    font.pixelSize: 13
    text: !lock ? ""
        : lock.authenticatingPassword ? "Checking…"
        : lock.failureMessage
    color: (lock && lock.failureMessage.length > 0) ? Services.Colors.critical
         : Services.Colors.textMuted
    opacity: text.length > 0 ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: Services.Motion.effectsFast
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Services.Motion.emphasizedDecelerate
        }
    }
}
