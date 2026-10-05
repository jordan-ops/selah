import QtQuick
import "../services" as Services

// The password field, shared by every lock style — same one the original
// centered layout drew inline. All auth state lives on `lock` (the
// LockScreen root): this only renders it and hands the typed password
// back. The preview passes interactive=false, which disables the input
// (no focus stealing from the settings window) and drops the click layer.
Rectangle {
    id: field

    property var lock: null
    property bool interactive: true
    property real fieldWidth: 460

    width: fieldWidth
    height: 48
    radius: 12
    color: Services.Colors.surface
    border.width: 1
    border.color: (lock && lock.failureMessage.length > 0) ? Services.Colors.critical
                : input.activeFocus ? Services.Colors.accent
                : Services.Colors.low

    Behavior on border.color {
        ColorAnimation {
            duration: Services.Motion.short3
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Services.Motion.standardCurve
        }
    }

    // what every style's focusField() funnels into
    function forceFocus() {
        if (interactive) input.forceActiveFocus()
    }

    TextInput {
        id: input
        font.family: Services.Fonts.family
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        verticalAlignment: TextInput.AlignVCenter
        color: Services.Colors.text
        selectionColor: Services.Colors.accent
        selectedTextColor: Services.Colors.background
        font.pixelSize: 15
        echoMode: TextInput.Password
        passwordCharacter: "●"
        enabled: interactive && lock && lock.lockRequested && !lock.authenticatingPassword
        focus: interactive && lock && lock.lockRequested

        onAccepted: {
            if (lock) lock.submitPassword(text)
            text = ""
        }
        Keys.onEscapePressed: {
            text = ""
            if (lock) lock.failureMessage = ""
        }
    }

    Text {
        font.family: Services.Fonts.family
        visible: input.text.length === 0
                 && !(lock && lock.authenticatingPassword)
        anchors.verticalCenter: parent.verticalCenter
        anchors.left: parent.left
        anchors.leftMargin: 16
        text: "Password"
        font.pixelSize: 15
        color: Services.Colors.textMuted
    }
}
