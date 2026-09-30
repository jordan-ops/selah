import Quickshell.Io
import QtQuick
import "../services" as Services

// Same row-of-actions layout as before, just restyled: bigger rounded-square
// swatch buttons instead of small 36px circles, matching the visual language
// of the theme picker's swatches. Extracted out of Bar.qml, same as
// PillThemeContent — Bar.qml just does `PillPowerContent { active: ... }`.
Row {
    id: root
    property bool active: false
    // powerProcess (the actual Process that runs the shutdown/reboot/etc
    // command) lives in Bar.qml, not in this file — QML ids don't cross
    // file boundaries. Emit a signal instead and let Bar.qml wire it up.
    // var, not string: modelData.command is an argv ARRAY — a string
    // signal coerces it to "systemctl,reboot", which Process then treats
    // as a single unfindable binary and every power action silently dies
    signal actionTriggered(var command)

    anchors.centerIn: parent
    spacing: 14
    opacity: active ? 1 : 0
    visible: active || opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

    Repeater {
        model: Services.PowerMenu.actions
        Rectangle {
            width: 64
            height: 64
            radius: 12
            color: itemArea.containsMouse ? Services.Colors.surface : "transparent"
            border.width: itemArea.containsMouse ? 2 : 0
            border.color: Services.Colors.accent

            // hover feedback — the swatch lights up under the cursor
            // instead of snapping to it
            Behavior on color {
                ColorAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }
            Behavior on border.width {
                NumberAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }

            // M3 staggered entrance: actions cascade in when the menu opens
            opacity: root.active ? 1 : 0
            Behavior on opacity {
                SequentialAnimation {
                    PauseAnimation { duration: Services.Motion.staggerDelay(index) }
                    NumberAnimation {
                        duration: Services.Motion.emphasizedEnter
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }
            }

            Text {
                font.family: Services.Fonts.family
                anchors.centerIn: parent
                text: modelData.icon
                color: Services.Colors.text
                font.pixelSize: 26
            }

            MouseArea {
                id: itemArea
                anchors.fill: parent
                hoverEnabled: true
                onClicked: {
                    root.actionTriggered(modelData.command)
                    Services.PowerMenu.open = false
                }
            }
        }
    }
}
