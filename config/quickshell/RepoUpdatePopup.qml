import QtQuick
import Quickshell
import Quickshell.Wayland
import "./services" as Services

// "A new version is ready" dialog — the deploy counterpart of
// UpdatesPopup (which lists pending PACKAGES). Services.Updates decides
// when it's shown: git says the clone is behind origin and that sha
// hasn't been dismissed. One centered card on the focused screen, same
// Variants/owns pattern as AetherPicker so exactly one surface ever
// claims keyboard focus. The input mask is the card itself, so clicks
// anywhere around it pass straight through to whatever is underneath —
// it dims the screen without trapping the pointer. Esc = Later.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        readonly property bool owns: Services.Updates.repoPopupOpen
            && Services.Updates.repoOwner !== ""
            && Services.Updates.repoOwner === (modelData ? modelData.name : "")

        visible: owns
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: owns ? WlrKeyboardFocus.Exclusive
                                          : WlrKeyboardFocus.None
        WlrLayershell.namespace: "selah-update"
        mask: Region { item: dialog }

        readonly property color bg: Services.Colors.background
        readonly property color fg: Services.Colors.text
        readonly property color dim: Services.Colors.textMuted
        readonly property color accent: Services.Colors.accent

        readonly property bool running: Services.Updates.repoApply === "running"
        readonly property bool failed: Services.Updates.repoApply === "failed"

        Item {
            anchors.fill: parent
            focus: win.owns
            Keys.onEscapePressed: Services.Updates.later()
        }

        // purely visual dim — the mask keeps it input-transparent
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.45)
        }

        Rectangle {
            id: dialog
            width: 380
            height: col.implicitHeight + 40
            anchors.centerIn: parent
            radius: 18
            color: win.bg
            border.color: Services.Colors.low
            border.width: 1

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

            Column {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 20
                spacing: 8

                Text {
                    width: parent.width
                    font.family: Services.Fonts.family
                    font.pixelSize: 15
                    font.bold: true
                    color: win.failed ? Services.Colors.critical : win.fg
                    text: win.running ? "Updating…"
                         : win.failed ? "Couldn’t update"
                         : "Update available"
                }

                Text {
                    width: parent.width
                    wrapMode: Text.WordWrap
                    font.family: Services.Fonts.family
                    font.pixelSize: 12
                    color: win.dim
                    text: win.running
                        ? "Fetching the new version and re-applying your config. The shell reloads when it lands."
                        : win.failed
                        ? "The pull or the config pass failed. Details are in\n~/.local/state/quickshell/repo-update.log — fix, then retry."
                        : "A new version of your desktop has been published. Update now — or later, and you’ll see this again for the next one."
                }

                Text {
                    width: parent.width
                    visible: !win.running && Services.Updates.localSha.length >= 7
                             && Services.Updates.remoteSha.length >= 7
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    color: win.dim
                    text: Services.Updates.localSha.slice(0, 7) + "  →  "
                          + Services.Updates.remoteSha.slice(0, 7)
                }

                Row {
                    width: parent.width
                    spacing: 10
                    layoutDirection: Qt.RightToLeft

                    Rectangle {
                        width: updT.implicitWidth + 34
                        height: 32
                        radius: 16
                        color: win.running ? Services.Colors.surface : win.accent
                        opacity: win.running ? 0.6 : 1

                        Text {
                            id: updT
                            anchors.centerIn: parent
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                            font.bold: true
                            color: win.running ? win.dim : win.bg
                            text: win.failed ? "Retry" : "Update"
                        }

                        MouseArea {
                            anchors.fill: parent
                            enabled: !win.running
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Updates.applyRepo()
                        }
                    }

                    Rectangle {
                        visible: !win.running
                        width: lateT.implicitWidth + 34
                        height: 32
                        radius: 16
                        color: lateMouse.containsMouse
                             ? Services.Colors.surfaceAlt : Services.Colors.surface

                        Text {
                            id: lateT
                            anchors.centerIn: parent
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                            color: win.fg
                            text: "Later"
                        }

                        MouseArea {
                            id: lateMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Updates.later()
                        }
                    }
                }
            }
        }
    }
}
