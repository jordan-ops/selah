import QtQuick
import "./services" as Services

// Destructive-action confirmation — a modal card over the settings
// window (SettingsWindow instantiates one, anchored center of the
// panel: radius 16, surface fill, low border — the elevated-card
// pattern the rest of the window uses; the confirm button carries the
// critical color so "this deletes something" reads at a glance).
//
// Usage from any file: instantiate once, then
//   confirmDlg.ask("Remove “ctrl+alt+x”?", "The binding is deleted from binds.lua and Hyprland reloads.", "Remove", fn)
// One click on the confirm button, or Enter, runs it; Escape, the
// cancel button, or a click on the scrim dismisses without action.
Item {
    id: root

    property bool open: false
    property string title: ""
    property string body: ""
    property string confirmLabel: "Confirm"
    property var onConfirm: null

    focus: open   // keep key events here while a confirm is up

    function ask(title, body, confirmLabel, onConfirm) {
        root.title = String(title || "")
        root.body = String(body || "")
        root.confirmLabel = String(confirmLabel || "Confirm")
        root.onConfirm = onConfirm
        root.open = true
        root.forceActiveFocus()
    }

    function accept() {
        const fn = root.onConfirm
        root.open = false
        root.onConfirm = null
        if (fn) fn()
    }

    function cancel() {
        root.open = false
        root.onConfirm = null
    }

    visible: opacity > 0.01
    opacity: open ? 1 : 0

    Behavior on opacity {
        NumberAnimation {
            duration: Services.Motion.effects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Services.Motion.emphasizedDecelerate
        }
    }

    Keys.onPressed: (event) => {
        if (!root.open) return
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.accept()
            event.accepted = true
        } else if (event.key === Qt.Key_Escape) {
            root.cancel()
            event.accepted = true
        }
    }

    // scrim — click away cancels; dims the window under the card
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(Services.Colors.background.r, Services.Colors.background.g,
                       Services.Colors.background.b, 0.55)
        opacity: root.open ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                duration: Services.Motion.effects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.emphasizedDecelerate
            }
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.open
            cursorShape: Qt.PointingHandCursor
            onClicked: root.cancel()
        }
    }

    // the card — springs in on the pop spring (spatial = bounce in M3E)
    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(parent.width - 120, 420)
        // 22 margins top/bottom + title/body column + 16 gap + 30px row
        height: cardCol.implicitHeight + 90
        radius: 16
        color: Services.Colors.surface
        border.color: Services.Colors.low
        border.width: 1
        opacity: root.open ? 1 : 0
        scale: root.open ? 1 : 0.92

        Behavior on opacity {
            NumberAnimation {
                duration: Services.Motion.effects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.emphasizedDecelerate
            }
        }
        Behavior on scale {
            SpringAnimation {
                spring: Services.Motion.popSpring
                damping: Services.Motion.popDamping
            }
        }

        Column {
            id: cardCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 22
            spacing: 8

            Text {
                font.family: Services.Fonts.family
                width: parent.width
                text: root.title
                font.pixelSize: 14
                font.bold: true
                color: Services.Colors.text
                wrapMode: Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: 3
            }
            Text {
                font.family: Services.Fonts.family
                visible: root.body !== ""
                width: parent.width
                text: root.body
                font.pixelSize: 12
                color: Services.Colors.textMuted
                wrapMode: Text.Wrap
            }
        }

        Row {
            id: btnRow
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.top: cardCol.bottom
            anchors.topMargin: 16
            spacing: 8

                Rectangle {
                    id: cancelBtn
                    width: cancelLbl.width + 30
                    height: 30
                    radius: 15
                    color: cancelMa.containsMouse ? Services.Colors.surfaceAlt
                                                  : Services.Colors.background
                    Accessible.role: Accessible.Button
                    Accessible.name: "Cancel"

                    Behavior on color {
                        ColorAnimation {
                            duration: Services.Motion.effectsFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }

                    Text {
                        id: cancelLbl
                        anchors.centerIn: parent
                        font.family: Services.Fonts.family
                        text: "Cancel"
                        font.pixelSize: 13
                        font.bold: true
                        color: Services.Colors.text
                    }
                    MouseArea {
                        id: cancelMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.cancel()
                    }
                }

                Rectangle {
                    id: confirmBtn
                    width: confirmLbl.width + 34
                    height: 30
                    radius: 15
                    color: confirmMa.containsMouse ? Services.Colors.critical
                                                   : Qt.rgba(Services.Colors.critical.r,
                                                             Services.Colors.critical.g,
                                                             Services.Colors.critical.b, 0.82)
                    border.color: Services.Colors.background
                    border.width: root.activeFocus ? 1 : 0
                    Accessible.role: Accessible.Button
                    Accessible.name: root.confirmLabel

                    Text {
                        id: confirmLbl
                        anchors.centerIn: parent
                        font.family: Services.Fonts.family
                        text: root.confirmLabel
                        font.pixelSize: 13
                        font.bold: true
                        color: Services.Colors.text
                    }
                    MouseArea {
                        id: confirmMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.accept()
                    }
                }
        }
    }
}
