import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Stateful toggle backed by read+toggle shell commands — the `cmdswitch`
// row type, for booleans that live outside hyprctl (nmcli radio,
// bluetoothctl power, pactl mute). e.readCommand's stdout is scanned for
// e.readTrue to light the pill; flipping runs e.command (the same
// read-invert-write bash the action rows used) and re-reads after, so
// the pill always shows what the system holds. On/Off text sits beside
// the pill so the state is readable at a glance.
Item {
    id: root

    property var e: null
    property bool on: false
    readonly property real extraHeight: 0

    width: 76
    height: 24

    function read() {
        if (!e || !e.readCommand) return
        rd.command = e.readCommand
        rd.running = true
    }
    function flip() {
        if (!e || !e.command) return
        act.command = e.command
        act.running = true
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
        onExited: root.read()
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
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            height: 24
            radius: 12
            color: root.on ? Services.Colors.accent : Services.Colors.surface

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: root.on ? parent.width - width - 3 : 3
                width: 18
                height: 18
                radius: 9
                color: root.on ? Services.Colors.background : Services.Colors.textMuted

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
