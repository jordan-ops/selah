import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../services" as Services

// Voice assistant card — the `voicecard` row type, Audio page. Voice is
// an OPT-IN feature: the shell ships with voice.enabled false in the
// settings store, and while it stays false ~/.local/bin/selah-voice is
// a no-op (no mic, no capsule, no downloads). This card is the whole
// lifecycle:
//
//   off + not set up → "Set up voice" explains the download (~215 MB
//                      of models, ONE password prompt for the pacman
//                      leg) and runs ~/.local/bin/selah-voice-setup,
//                      streaming its step lines into the progress row
//   ready + off      → the toggle enables instantly (everything's
//                      already on disk)
//   on               → toggle off is instant too; models stay put, so
//                      re-enabling is free. A "Test voice" chip plays
//                      one Piper line to prove the chain end to end.
//
// Live class, no Apply/Revert — same as the cmdswitch rows: the store
// write IS the state. The `--check` probe re-runs every few seconds
// while the page shows this card, so a cancelled setup, an external
// `rm`, or a finished download all land without a reopen.
Item {
    id: root

    property var e: null

    readonly property bool enabled: Services.Settings.voiceEnabled
    // "ready" or the first "missing: …" line from the check probe
    property string checkResult: "missing: probing…"
    readonly property bool ready: checkResult === "ready"
    readonly property bool installing: setupProc.running
    // the step line the installer most recently printed (or its error)
    property string setupStep: ""

    height: col.implicitHeight
    readonly property real extraHeight: col.implicitHeight - 64

    function refreshCheck() {
        checkProc.running = false
        checkProc.running = true
    }
    Component.onCompleted: refreshCheck()

    // cheap probe — but gated on the window too: the card outlives a
    // closed settings (pageEntries doesn't reset on close), so without
    // this the 3 s check keeps spawning after one visit to Audio.
    Timer {
        interval: 3000; repeat: true
        running: Services.SettingsApp.open && !root.installing
        onTriggered: root.refreshCheck()
    }

    Process {
        id: checkProc
        command: [Quickshell.env("HOME") + "/.local/bin/selah-voice-setup", "--check"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n").filter(l => l.trim() !== "")
                root.checkResult = lines.length > 0 ? lines[0].trim() : "missing: setup probe failed"
            }
        }
    }

    Process {
        id: setupProc
        command: [Quickshell.env("HOME") + "/.local/bin/selah-voice-setup"]
        // every step line lands in the progress row as it happens
        stdout: SplitParser {
            onRead: line => {
                const t = line.trim()
                if (t !== "") root.setupStep = t
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                const first = text.trim().split("\n")[0]
                if (first !== "") root.setupStep = first
            }
        }
        onExited: {
            root.setupStep = ""
            root.refreshCheck()
        }
    }

    Process {
        id: testProc
    }

    // ——— the card ———
    Column {
        id: col
        width: parent.width
        spacing: 8

        Rectangle {
            width: col.width
            height: row1.implicitHeight + 28
            radius: 16
            color: Services.Colors.surface
            border.color: Services.Colors.low
            border.width: 1

            Row {
                id: row1
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                IconImage {
                    anchors.verticalCenter: parent.verticalCenter
                    implicitSize: 20
                    source: Quickshell.iconPath("audio-input-microphone-symbolic",
                                                "microphone-sensor-symbolic")
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - 20 - statusTxt.width - 44 - 30
                    spacing: 2

                    Text {
                        width: parent.width
                        font.family: Services.Fonts.family
                        font.pixelSize: 13
                        font.bold: true
                        color: Services.Colors.text
                        text: "Voice assistant"
                    }
                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        font.family: Services.Fonts.family
                        font.pixelSize: 11
                        color: root.installing ? Services.Colors.accent
                            : Services.Colors.textMuted
                        text: root.installing ? "Setting up…"
                            : root.ready && root.enabled ? "On — tap SUPER+D, speak, tap again to send"
                            : root.ready ? "Ready to enable — dictation that answers out loud"
                            : "Not set up — SUPER+D stays quiet until it is"
                    }
                }

                Text {
                    id: statusTxt
                    anchors.verticalCenter: parent.verticalCenter
                    width: 24
                    horizontalAlignment: Text.AlignRight
                    font.family: Services.Fonts.family
                    font.pixelSize: 12
                    font.bold: true
                    color: root.enabled ? Services.Colors.accent : Services.Colors.textMuted
                    text: root.enabled ? "On" : "Off"

                    Behavior on color {
                        ColorAnimation {
                            duration: Services.Motion.effectsFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }
                }

                // the same pill every other switch in the settings wears
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 44
                    height: 24
                    radius: 12
                    color: root.enabled ? Services.Colors.accent : Services.Colors.surface
                    border.color: Services.Colors.low
                    border.width: root.enabled ? 0 : 1

                    Accessible.role: Accessible.Button
                    Accessible.name: "Voice assistant — " + (root.enabled ? "on" : "off")

                    Behavior on color {
                        ColorAnimation {
                            duration: Services.Motion.effectsFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        x: root.enabled ? parent.width - width - 3 : 3
                        width: 18
                        height: 18
                        radius: 9
                        color: root.enabled ? Services.Colors.background : Services.Colors.textMuted

                        Behavior on x {
                            SpringAnimation {
                                spring: Services.Motion.bounceSpring
                                damping: Services.Motion.bounceDamping
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Settings.set("voice.enabled", String(!root.enabled))
                    }
                }
            }
        }

        // ——— the second row: setup / progress / test ———
        Rectangle {
            visible: !root.ready || root.enabled
            width: col.width
            height: sub.implicitHeight + 24
            radius: 16
            color: Services.Colors.surface
            border.color: Services.Colors.low
            border.width: 1

            Row {
                id: sub
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 10

                // installing: the live step + an indeterminate shimmer
                Column {
                    visible: root.installing
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - setupChip.width - 10
                    spacing: 5

                    Text {
                        width: parent.width
                        elide: Text.ElideRight
                        font.family: Services.Fonts.family
                        font.pixelSize: 11
                        color: Services.Colors.text
                        text: root.setupStep !== "" ? root.setupStep : "Working…"
                    }
                    Rectangle {
                        id: shimmerTrack
                        width: parent.width
                        height: 3
                        radius: 1.5
                        color: Services.Colors.low
                        clip: true
                        // 0→1 sweep carrier for the moving segment below
                        property real sweep: 0

                        Rectangle {
                            width: shimmerTrack.width * 0.3
                            height: 3
                            radius: 1.5
                            color: Services.Colors.accent
                            x: (shimmerTrack.width - width) * shimmerTrack.sweep
                        }

                        SequentialAnimation {
                            loops: Animation.Infinite
                            running: root.installing
                            NumberAnimation {
                                target: shimmerTrack; property: "sweep"
                                from: 0; to: 1; duration: 900
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Services.Motion.emphasizedDecelerate
                            }
                            NumberAnimation {
                                target: shimmerTrack; property: "sweep"
                                from: 1; to: 0; duration: 900
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Services.Motion.emphasizedDecelerate
                            }
                        }
                    }
                }

                Text {
                    visible: !root.installing
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - setupChip.width - 10
                    elide: Text.ElideRight
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    color: Services.Colors.textMuted
                    text: root.ready
                        ? "Test line plays through Piper — SUPER+D dictation goes straight into the session"
                        : "Downloads the speech engine (~215 MB) and may ask your password once for audio tools"
                }

                // primary chip: setup now (doubles as retry after a
                // cancelled prompt or a failed download)
                Rectangle {
                    id: setupChip
                    visible: !root.ready
                    anchors.verticalCenter: parent.verticalCenter
                    width: setupTxt.implicitWidth + 26
                    height: 26
                    radius: 13
                    color: setupMa.containsMouse ? Services.Colors.accentSurface
                        : Services.Colors.accent

                    Text {
                        id: setupTxt
                        anchors.centerIn: parent
                        font.family: Services.Fonts.family
                        font.pixelSize: 12
                        font.bold: true
                        color: Services.Colors.background
                        text: "Set up voice"
                    }
                    MouseArea {
                        id: setupMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            root.setupStep = "Starting…"
                            setupProc.running = false
                            setupProc.running = true
                        }
                    }
                }

                // ready + on: prove the whole chain with one spoken line
                Rectangle {
                    id: testChip
                    visible: root.ready && root.enabled
                    anchors.verticalCenter: parent.verticalCenter
                    width: testTxt.implicitWidth + 26
                    height: 26
                    radius: 13
                    color: testMa.containsMouse ? Services.Colors.surfaceAlt
                        : Services.Colors.surface
                    border.color: Services.Colors.low
                    border.width: 1

                    Text {
                        id: testTxt
                        anchors.centerIn: parent
                        font.family: Services.Fonts.family
                        font.pixelSize: 12
                        font.bold: true
                        color: Services.Colors.text
                        text: "Test voice"
                    }
                    MouseArea {
                        id: testMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            testProc.command = [Quickshell.env("HOME") + "/.local/bin/selah-speak",
                                                "Voice assistant is ready."]
                            testProc.running = false
                            testProc.running = true
                        }
                    }
                }
            }
        }
    }
}
