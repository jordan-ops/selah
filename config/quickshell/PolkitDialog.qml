import QtQuick
import Quickshell
import Quickshell.Wayland
import "./services" as Services

// DEPRECATED — no longer instantiated (see shell.qml). The prompt now
// lives inside the bar as the pill's "polkit" mode (Bar.qml), merged
// like the launcher per user request; this file is kept as the reference
// for the auth-flow UI it used to draw.
//
// PolicyKit authentication dialog — one centered card per screen set,
// shown only on the screen that had focus when the request started
// (Services.Polkit.ownerScreen). Same Variants/owns pattern as
// RepoUpdatePopup so exactly one surface ever claims keyboard focus.
//
// Unlike every other popup in this shell there is NO outside-click
// dismissal: an auth request is refused explicitly (Esc or Cancel),
// never by clicking on the scrim. The scrim also swallows clicks
// instead of passing them through — you don't interact with apps
// underneath while a password prompt is pending. Keyboard focus is
// Exclusive while visible, so keys reach the field no matter what had
// focus before the prompt appeared.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        readonly property bool owns: Services.Polkit.open
            && Services.Polkit.ownerScreen !== ""
            && Services.Polkit.ownerScreen === (modelData ? modelData.name : "")

        visible: owns
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qs-polkit"
        WlrLayershell.keyboardFocus: owns ? WlrKeyboardFocus.Exclusive
                                          : WlrKeyboardFocus.None

        readonly property color bg: Services.Colors.background
        readonly property color fg: Services.Colors.text
        readonly property color dim: Services.Colors.textMuted
        readonly property color accent: Services.Colors.accent
        readonly property color critical: Services.Colors.critical

        readonly property var flow: Services.Polkit.flow

        // strictly visual dim — the window itself is the input sink
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        // absorbs clicks (no dismiss) and re-focuses the field so a
        // stray click never leaves the prompt typed into nowhere
        MouseArea {
            anchors.fill: parent
            onClicked: field.forceActiveFocus()
        }

        onVisibleChanged: {
            if (visible) {
                field.text = ""
                Qt.callLater(() => field.forceActiveFocus())
            }
        }

        Rectangle {
            id: dialog
            width: 400
            height: col.implicitHeight + 40
            anchors.centerIn: parent
            anchors.horizontalCenterOffset: shakeOffset
            radius: 18
            color: win.bg
            border.color: Services.Colors.low
            border.width: 1

            // wrong-password shake target (omarchy's shakeOffset pattern)
            property real shakeOffset: 0

            opacity: win.owns ? 1 : 0
            scale: win.owns ? 1 : 0.94
            transformOrigin: Item.Center

            Behavior on opacity {
                NumberAnimation {
                    duration: Services.Motion.effects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }
            Behavior on scale {
                SpringAnimation {
                    spring: Services.Motion.spatialFastSpring
                    damping: Services.Motion.spatialFastDamping
                }
            }

            SequentialAnimation {
                id: shake
                NumberAnimation { target: dialog; property: "shakeOffset"; to: -8; duration: 35; easing.type: Easing.OutQuad }
                NumberAnimation { target: dialog; property: "shakeOffset"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
                NumberAnimation { target: dialog; property: "shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
            }
            Connections {
                target: Services.Polkit
                function onFailuresChanged() {
                    if (Services.Polkit.failures > 0) {
                        field.text = ""   // never keep the wrong password around
                        shake.restart()
                    }
                }
            }

            // Esc cancels even when focus sits outside the field (keys
            // bubble from the focused item up the parent chain, and the
            // field below marks Escape accepted so the two never fight)
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape) {
                    Services.Polkit.cancel()
                    event.accepted = true
                }
            }

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 10

                // ── header: lock + title + machine-readable action ──
                Row {
                    width: parent.width
                    spacing: 12

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        color: Services.Polkit.errorFlash ? win.critical : win.accent

                        Behavior on color {
                            ColorAnimation {
                                duration: Services.Motion.effectsFast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Services.Motion.emphasizedDecelerate
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            text: "\uf023"   // nf-fa-lock
                            font.family: Services.Fonts.family
                            font.pixelSize: 17
                            color: win.bg
                        }
                    }

                    Column {
                        width: parent.width - 52
                        spacing: 2

                        Text {
                            width: parent.width
                            font.family: Services.Fonts.family
                            font.pixelSize: 15
                            font.bold: true
                            color: win.fg
                            text: "Authentication required"
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: win.flow && win.flow.actionId !== ""
                            font.family: Services.Fonts.family
                            font.pixelSize: 11
                            color: win.dim
                            text: win.flow ? win.flow.actionId : ""
                            elide: Text.ElideRight
                        }
                    }
                }

                // ── what polkitd wants done ──
                Text {
                    width: parent.width
                    visible: win.flow && win.flow.message !== ""
                    wrapMode: Text.WordWrap
                    font.family: Services.Fonts.family
                    font.pixelSize: 12
                    color: win.dim
                    text: win.flow ? win.flow.message : ""
                }

                Rectangle { width: parent.width; height: 1; color: Services.Colors.low }

                // ── account chips, only when the flow offers a choice ──
                Row {
                    width: parent.width
                    spacing: 6
                    visible: win.flow && win.flow.identities.length > 1

                    Text {
                        font.family: Services.Fonts.family
                        font.pixelSize: 11
                        font.bold: true
                        color: win.dim
                        text: "Account"
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Repeater {
                        model: win.flow ? win.flow.identities : []

                        Rectangle {
                            id: chip
                            required property var modelData
                            readonly property bool selected:
                                win.flow && win.flow.selectedIdentity === modelData

                            width: chipLabel.width + 18
                            height: 24
                            radius: 12
                            color: selected ? win.accent : Services.Colors.surface

                            Text {
                                id: chipLabel
                                anchors.centerIn: parent
                                font.family: Services.Fonts.family
                                font.pixelSize: 11
                                font.bold: chip.selected
                                color: chip.selected ? win.bg : win.dim
                                text: String(chip.modelData)
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Polkit.pickIdentity(chip.modelData)
                            }
                        }
                    }
                }

                // ── password field ──
                Rectangle {
                    id: inputBox
                    width: parent.width
                    height: 38
                    radius: 10
                    color: Services.Colors.surface
                    border.width: field.activeFocus ? 1 : 0
                    border.color: win.accent

                    Behavior on border.color {
                        ColorAnimation {
                            duration: Services.Motion.effectsFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 12
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Services.Fonts.family
                        font.pixelSize: 13
                        color: Services.Polkit.errorFlash ? win.critical : win.dim
                        opacity: field.text === "" ? 1 : 0
                        text: Services.Polkit.submitted ? "Checking…"
                            : Services.Polkit.errorFlash ? "Wrong password"
                            : (win.flow && win.flow.inputPrompt !== "") ? win.flow.inputPrompt
                            : "Password"

                        Behavior on opacity {
                            NumberAnimation { duration: Services.Motion.effectsFast }
                        }
                    }

                    TextInput {
                        id: field
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        selectByMouse: true
                        font.family: Services.Fonts.family
                        font.pixelSize: 13
                        color: Services.Polkit.errorFlash ? win.critical : win.fg
                        selectionColor: win.accent
                        echoMode: (win.flow && win.flow.responseVisible)
                                  ? TextInput.Normal : TextInput.Password
                        passwordCharacter: "•"
                        readOnly: Services.Polkit.submitted

                        onAccepted: {
                            Services.Polkit.submit(text)
                            text = ""
                        }
                        Keys.onEscapePressed: {
                            Services.Polkit.cancel()
                            event.accepted = true
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        onClicked: field.forceActiveFocus()
                    }
                }

                // ── supplementary note / error line ──
                Text {
                    width: parent.width
                    visible: win.flow && win.flow.supplementaryMessage !== ""
                             && !Services.Polkit.submitted
                    wrapMode: Text.WordWrap
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    color: (win.flow && win.flow.supplementaryIsError)
                           || Services.Polkit.errorFlash ? win.critical : win.dim
                    text: win.flow ? win.flow.supplementaryMessage : ""
                }

                // ── actions ──
                Row {
                    width: parent.width
                    spacing: 8
                    layoutDirection: Qt.RightToLeft

                    Rectangle {
                        id: authBtn
                        width: authTxt.implicitWidth + 34
                        height: 32
                        radius: 16
                        color: win.accent
                        opacity: Services.Polkit.submitted ? 0.6 : 1

                        Text {
                            id: authTxt
                            anchors.centerIn: parent
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                            font.bold: true
                            color: win.bg
                            text: "Authenticate"
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !Services.Polkit.submitted
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                Services.Polkit.submit(field.text)
                                field.text = ""
                            }
                        }
                    }

                    Rectangle {
                        id: cancelBtn
                        width: cancelTxt.implicitWidth + 34
                        height: 32
                        radius: 16
                        color: cancelMouse.containsMouse
                               ? Services.Colors.surfaceAlt : Services.Colors.surface

                        Text {
                            id: cancelTxt
                            anchors.centerIn: parent
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                            color: win.fg
                            text: "Cancel"
                        }

                        MouseArea {
                            id: cancelMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Polkit.cancel()
                        }
                    }
                }
            }
        }
    }
}
