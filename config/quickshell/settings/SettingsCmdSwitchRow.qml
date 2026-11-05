import QtQuick
import Quickshell
import Quickshell.Io
import "../services" as Services

// Stateful toggle backed by read+toggle shell commands — the `cmdswitch`
// row type, for booleans that live outside hyprctl (nmcli radio,
// bluetoothctl power, pactl mute). e.readCommand's stdout is scanned for
// e.readTrue to light the pill; flipping runs e.command (the same
// read-invert-write bash the action rows used) and re-reads after, so
// the pill always shows what the system holds. A failed flip (nonzero
// exit or stderr) re-reads the REAL state back and raises an error
// toast — the pill never lies about a command that didn't land. On/Off
// text sits beside the pill so the state is readable at a glance.
// Color Behaviors + the pop-spring knob throw match
// SettingsHyprSwitchRow exactly, so all three switch types feel alike.
Item {
    id: root

    property var e: null
    property bool on: false
    readonly property real extraHeight: 0

    width: 76
    height: 24

    Accessible.role: Accessible.Button
    Accessible.name: (root.e && root.e.label ? root.e.label : "Toggle")
        + " — " + (root.on ? "on" : "off")

    function read() {
        if (!e || !e.readCommand) return
        rd.command = e.readCommand
        rd.running = true
    }
    function flip() { setTo(!root.on) }
    // named for the reset affordance in the row delegate — the toggle
    // command flips reality, so "set to" is really "flip when different"
    function setTo(target) {
        if (root.on === !!target) return
        if (!e || !e.command) return
        act.command = e.command
        act.running = true
    }
    function resetToDefault() {
        if (!root.e || root.e.default === undefined) return
        root.setTo(root.e.default === true || root.e.default === "true")
    }

    Component.onCompleted: read()

    Process {
        id: rd
        stdout: StdioCollector {
            onStreamFinished: {
                root.on = String(root.e ? root.e.readTrue : "").length > 0
                    && text.includes(String(root.e.readTrue))
            }
        }
    }
    Process {
        id: act
        // reality wins: always re-read, and when the command itself
        // broke, say so instead of leaving the old state silently
        onExited: (exitCode) => {
            root.read()
            if (exitCode !== 0 && root.e)
                SettingsToast.push("«" + root.e.label
                                   + "» failed — command not found?", true)
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const first = text.trim().split("\n")[0]
                if (first !== "" && root.e)
                    SettingsToast.push("«" + root.e.label + "» — " + first, true)
            }
        }
    }

    Row {
        anchors.fill: parent
        spacing: 8

        Text {
            font.family: Services.Fonts.family
            anchors.verticalCenter: parent.verticalCenter
            text: root.on ? "On" : "Off"
            font.pixelSize: 12
            font.bold: true
            color: root.on ? Services.Colors.accent : Services.Colors.textMuted
            horizontalAlignment: Text.AlignRight
            width: 24

            Behavior on color {
                ColorAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 24
            radius: 12
            color: root.on ? Services.Colors.accent : Services.Colors.surface

            Behavior on color {
                ColorAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: root.on ? parent.width - width - 3 : 3
                width: 18
                height: 18
                radius: 9
                color: root.on ? Services.Colors.background : Services.Colors.textMuted

                Behavior on color {
                    ColorAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }

                // knob throw — pop spring: overshoots the end stop, snaps back
                Behavior on x {
                    SpringAnimation {
                        spring: Services.Motion.popSpring
                        damping: Services.Motion.popDamping
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.flip()
            }
        }
    }
}
