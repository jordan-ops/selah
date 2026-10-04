// Parser/overlay adapted from Nebula shell (GPL-3.0)
//
// Keybinding cheat sheet — SUPER + slash (`qs ipc call cheatsheet toggle`).
// Full-screen scrim (click anywhere = close) plus one centered card listing
// every hl.bind in ~/.config/hypr/binds.lua, grouped under its
// `---- NAME ----` section header, key pills split on " + ", ESC closes.
//
// Structure follows the overlays Selah already has (RepoUpdatePopup /
// AetherPicker): a Variants over Quickshell.screens where only the screen
// that opened it (`Services.Keybinds.ownerScreen`) renders, so exactly one
// surface ever claims WlrKeyboardFocus.Exclusive — that exclusive focus is
// also what routes Escape to the focus Item below. Services.Keybinds owns
// the state and the parser; this file only draws it.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "./services" as Services

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        readonly property bool owns: Services.Keybinds.open
            && Services.Keybinds.ownerScreen !== ""
            && Services.Keybinds.ownerScreen === (modelData ? modelData.name : "")

        visible: owns
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: owns ? WlrKeyboardFocus.Exclusive
                                           : WlrKeyboardFocus.None
        WlrLayershell.namespace: "selah-cheatsheet"

        // Every duration/spring below comes from a Motion token, and the
        // tokens collapse to 0 (springs to the instant pair) while
        // Motion.motionOn is false — reduced motion gates them all there.
        Item {
            anchors.fill: parent
            focus: win.owns
            onVisibleChanged: if (visible) forceActiveFocus()
            Keys.onEscapePressed: Services.Keybinds.close()
        }

        // scrim — click anywhere outside the card to dismiss
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.6)
            opacity: win.owns ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Services.Motion.effects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: Services.Keybinds.close()
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: Math.min(parent.width - 96, 1180)
            height: Math.min(parent.height - 96, 860)
            radius: 18
            clip: true
            color: Services.Colors.background
            border.color: Services.Colors.low
            border.width: 1
            opacity: win.owns ? 1 : 0
            scale: win.owns ? 1 : 0.96
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

            // swallow clicks so they never fall through to the dismiss scrim
            MouseArea { anchors.fill: parent }

            // ---------- header ----------
            Item {
                id: header
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 20
                height: 30

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        font.family: Services.Fonts.family
                        text: "Keybindings"
                        font.pixelSize: 15
                        font.bold: true
                        color: Services.Colors.text
                    }
                    Text {
                        font.family: Services.Fonts.family
                        anchors.verticalCenter: parent.verticalCenter
                        text: Services.Keybinds.bindCount + " shortcuts"
                        font.pixelSize: 12
                        color: Services.Colors.textMuted
                    }
                }

                Rectangle {   // "esc closes" hint — the way out for mouse users
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: escT.implicitWidth + 18
                    height: 24
                    radius: 7
                    color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                   Services.Colors.text.b, 0.08)
                    border.color: Services.Colors.low
                    border.width: 1

                    Text {
                        id: escT
                        anchors.centerIn: parent
                        font.family: Services.Fonts.family
                        text: "ESC"
                        font.pixelSize: 11
                        font.bold: true
                        color: Services.Colors.textMuted
                    }
                }
            }

            Rectangle {
                id: line
                anchors.top: header.bottom
                anchors.topMargin: 14
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                height: 1
                color: Services.Colors.low
                opacity: 0.4
            }

            // ---------- groups: one column per section ----------
            Flickable {
                id: flick
                anchors.top: line.bottom
                anchors.topMargin: 16
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                anchors.bottomMargin: 20
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                contentWidth: width
                contentHeight: colsRow.implicitHeight
                interactive: contentHeight > height

                Row {
                    id: colsRow
                    width: flick.width
                    spacing: 34
                    // binds.lua carries a handful of sections, so one column
                    // each (no Nebula-style height balancing needed)
                    readonly property int n: Math.max(1, Services.Keybinds.groups.length)
                    readonly property real colWidth: (width - spacing * (n - 1)) / n

                    Repeater {
                        model: Services.Keybinds.groups

                        delegate: Column {
                            id: gcol
                            required property var modelData
                            width: colsRow.colWidth
                            spacing: 6

                            // group heading: accent caps + hairline, like the
                            // settings cards' section labels
                            Row {
                                width: gcol.width
                                height: 18
                                spacing: 8

                                Text {
                                    id: hdrT
                                    font.family: Services.Fonts.family
                                    text: gcol.modelData.name.toUpperCase()
                                    font.pixelSize: 10
                                    font.bold: true
                                    font.letterSpacing: 1.5
                                    color: Services.Colors.accent
                                    height: parent.height
                                    verticalAlignment: Text.AlignVCenter
                                }
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: Math.max(0, gcol.width - hdrT.implicitWidth - 8)
                                    height: 1
                                    color: Services.Colors.accent
                                    opacity: 0.2
                                }
                            }

                            Repeater {
                                model: gcol.modelData.binds

                                delegate: Item {
                                    id: row
                                    required property var modelData
                                    required property int index
                                    width: gcol.width
                                    height: 26

                                    // one pill per modifier — "SUPER + SHIFT + Q"
                                    // as a single cap is a sentence, three caps
                                    // are a picture
                                    Row {
                                        id: capsRow
                                        anchors.left: parent.left
                                        anchors.verticalCenter: parent.verticalCenter
                                        height: 24
                                        spacing: 3

                                        Repeater {
                                            model: String(row.modelData.chord).split(" + ")

                                            delegate: Rectangle {
                                                id: cap
                                                required property string modelData
                                                // XF86 prefixes eat half a column
                                                // and say nothing — every reader
                                                // knows an AudioRaiseVolume key
                                                readonly property string label:
                                                    modelData.replace(/^XF86/, "")
                                                width: Math.max(26, capT.implicitWidth + 14)
                                                height: 24
                                                radius: 7
                                                color: Qt.rgba(Services.Colors.text.r,
                                                               Services.Colors.text.g,
                                                               Services.Colors.text.b, 0.08)
                                                border.color: Services.Colors.low
                                                border.width: 1

                                                Text {
                                                    id: capT
                                                    anchors.centerIn: parent
                                                    font.family: Services.Fonts.family
                                                    text: cap.label
                                                    font.pixelSize: 11
                                                    font.bold: true
                                                    color: Services.Colors.accent
                                                }
                                            }
                                        }
                                    }

                                    Text {
                                        anchors.left: capsRow.right
                                        anchors.leftMargin: 10
                                        anchors.right: parent.right
                                        anchors.verticalCenter: parent.verticalCenter
                                        font.family: Services.Fonts.family
                                        text: row.modelData.desc
                                        font.pixelSize: 12
                                        color: Services.Colors.textMuted
                                        elide: Text.ElideRight
                                    }

                                    Rectangle {
                                        anchors.bottom: parent.bottom
                                        width: parent.width
                                        height: 1
                                        color: Services.Colors.low
                                        opacity: row.index === gcol.modelData.binds.length - 1
                                            ? 0 : 0.3
                                    }
                                }
                            }
                        }
                    }
                }

                // empty state — the file moved or is unreadable
                Text {
                    visible: Services.Keybinds.groups.length === 0
                    anchors.centerIn: parent
                    font.family: Services.Fonts.family
                    text: "couldn't read ~/.config/hypr/binds.lua"
                    font.pixelSize: 13
                    color: Services.Colors.textMuted
                }
            }
        }
    }
}
