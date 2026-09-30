import QtQuick
import "./services" as Services

Rectangle {
    id: root
    width: 260
    height: 300
    radius: 18
    color: Services.Colors.background

    // Escape closes. The popup only holds keyboard focus while the bar's
    // HyprlandFocusGrab (windows: [recordingPopup], active: open) is up, so
    // this handler is live exactly while the popup is up. Handlers fire on
    // the focused item then bubble to ancestors, so the buttons below do not
    // shadow it — none of them accept keys.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            Services.ScreenRecording.close()
            event.accepted = true
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 14

        // HEADER. No anchors inside a Row — Qt refuses outright: "Cannot
        // specify left, right, horizontalCenter, fill or centerIn anchors for
        // items inside Row. Row will not function." (which is exactly what it
        // threw when this header used anchors.left / anchors.right.) So the
        // title is sized to the Row's leftover width instead, which left-aligns
        // it by construction, and the close button follows as the last child.
        Row {
            width: parent.width
            // Row does not vertically centre its children — it places them at
            // their own y, defaulting to 0. Both children are given the full
            // height so they align to it instead of sitting on top of the line.
            height: 22

            Text {
                font.family: Services.Fonts.family
                height: parent.height
                width: Math.max(0, parent.width - closeBtn.width)
                verticalAlignment: Text.AlignVCenter
                text: "Screen Recording"
                font.pixelSize: 14
                font.bold: true
                color: Services.Colors.text
            }

            // Explicit close, so the popup is never a one-way door — the
            // control center's record tile now opens this, and before this
            // the only ways out were clicking away or a Hyprland focus-grab
            // clear, neither of which is discoverable.
            Rectangle {
                id: closeBtn
                width: 22; height: 22; radius: 11
                color: closeArea.containsMouse ? Services.Colors.surface : "transparent"

                Text {
                    font.family: Services.Fonts.family
                    anchors.centerIn: parent
                    text: "✕"
                    font.pixelSize: 12
                    color: closeArea.containsMouse ? Services.Colors.text : Services.Colors.text_muted
                }

                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    onClicked: Services.ScreenRecording.close()
                }
            }
        }

        // Big elapsed display while recording, otherwise show setup/error
        // state instead of pretending the recorder is ready after a failure.
        Text {
            font.family: Services.Fonts.family
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: Services.ScreenRecording.recording
                ? Services.ScreenRecording.elapsedDisplay
                : Services.ScreenRecording.starting
                    ? "Starting…"
                    : Services.ScreenRecording.lastError !== ""
                        ? Services.ScreenRecording.lastError
                        : "Ready"
            font.pixelSize: Services.ScreenRecording.recording ? 30
                : Services.ScreenRecording.starting ? 18
                : Services.ScreenRecording.lastError !== "" ? 11 : 14
            font.weight: Font.Light
            color: Services.ScreenRecording.recording
                || Services.ScreenRecording.lastError !== ""
                ? "#e06060" : Services.Colors.text_muted
            elide: Text.ElideRight
        }

        // ---------------- Capture target ----------------
        Column {
            width: parent.width
            spacing: 6
            visible: !Services.ScreenRecording.recording && !Services.ScreenRecording.starting

            Text { font.family: Services.Fonts.family; text: "Capture"; font.pixelSize: 11; color: Services.Colors.text_muted }

            Row {
                width: parent.width
                spacing: 8

                Repeater {
                    model: [
                        { key: "screen", label: "Screen" },
                        { key: "window", label: "Window" },
                        { key: "region", label: "Region" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: (parent.width - 16) / 3
                        height: 30
                        radius: 8
                        property bool active: Services.ScreenRecording.captureTarget === modelData.key
                        color: active
                            ? Qt.rgba(Services.Colors.accent.r, Services.Colors.accent.g, Services.Colors.accent.b, 0.18)
                            : Services.Colors.surface

                        Text {
                            font.family: Services.Fonts.family
                            anchors.centerIn: parent
                            text: modelData.label
                            font.pixelSize: 11
                            color: active ? Services.Colors.accent : Services.Colors.text
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Services.ScreenRecording.setCaptureTarget(modelData.key)
                        }
                    }
                }
            }
        }

        // ---------------- Audio ----------------
        Column {
            width: parent.width
            spacing: 6
            visible: !Services.ScreenRecording.recording && !Services.ScreenRecording.starting

            Text { font.family: Services.Fonts.family; text: "Audio"; font.pixelSize: 11; color: Services.Colors.text_muted }

            Row {
                width: parent.width
                spacing: 8

                Rectangle {
                    width: (parent.width - 8) / 2
                    height: 30
                    radius: 8
                    color: Services.ScreenRecording.audioMic
                        ? Qt.rgba(Services.Colors.accent.r, Services.Colors.accent.g, Services.Colors.accent.b, 0.18)
                        : Services.Colors.surface
                    Text {
                        font.family: Services.Fonts.family
                        anchors.centerIn: parent
                        text: "Mic"
                        font.pixelSize: 11
                        color: Services.ScreenRecording.audioMic ? Services.Colors.accent : Services.Colors.text
                    }
                    MouseArea { anchors.fill: parent; onClicked: Services.ScreenRecording.toggleMic() }
                }

                Rectangle {
                    width: (parent.width - 8) / 2
                    height: 30
                    radius: 8
                    color: Services.ScreenRecording.audioSystem
                        ? Qt.rgba(Services.Colors.accent.r, Services.Colors.accent.g, Services.Colors.accent.b, 0.18)
                        : Services.Colors.surface
                    Text {
                        font.family: Services.Fonts.family
                        anchors.centerIn: parent
                        text: "System"
                        font.pixelSize: 11
                        color: Services.ScreenRecording.audioSystem ? Services.Colors.accent : Services.Colors.text
                    }
                    MouseArea { anchors.fill: parent; onClicked: Services.ScreenRecording.toggleSystem() }
                }
            }
        }

        // ---------------- Start / Stop / Discard ----------------
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 10

            Rectangle {
                visible: !Services.ScreenRecording.recording && !Services.ScreenRecording.starting
                width: 140; height: 36; radius: 18
                // Same fix as the bar's rec chip: this was an 18% red wash
                // with #e06060 on it, i.e. red-on-red and washed out. Start
                // is this popup's primary action, so it gets the same solid
                // critical fill with white text (~3.8:1) as the bar chip.
                color: Services.Colors.critical
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.22)
                Text {
                    font.family: Services.Fonts.family
                    anchors.centerIn: parent
                    text: "● Start"
                    font.pixelSize: 13
                    font.bold: true
                    color: "#ffffff"
                }
                MouseArea { anchors.fill: parent; onClicked: Services.ScreenRecording.startRecording() }
            }

            Rectangle {
                visible: Services.ScreenRecording.recording
                width: 100; height: 36; radius: 18
                color: Services.Colors.surface
                Text { font.family: Services.Fonts.family; anchors.centerIn: parent; text: "Stop"; font.pixelSize: 13; color: Services.Colors.text }
                MouseArea { anchors.fill: parent; onClicked: Services.ScreenRecording.stopRecording() }
            }

            Rectangle {
                visible: Services.ScreenRecording.recording
                width: 100; height: 36; radius: 18
                color: Qt.rgba(0.5, 0.5, 0.5, 0.12)
                Text { font.family: Services.Fonts.family; anchors.centerIn: parent; text: "Discard"; font.pixelSize: 13; color: Services.Colors.text_muted }
                MouseArea { anchors.fill: parent; onClicked: Services.ScreenRecording.discardRecording() }
            }
        }
    }
}
