import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import "./modules"
import "./services"

PanelWindow {
    id: toplevel
    anchors { top: true; right: true }
    implicitWidth: 140
    implicitHeight: 50
    margins.right: 12
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore

    MediaPill {
        id: pill
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 3
    }

    PopupWindow {
        id: popup
        anchor.window: toplevel
        anchor.rect.x: toplevel.implicitWidth - implicitWidth - 12
        anchor.rect.y: 50
        implicitWidth: 480
        implicitHeight: 220
        color: "transparent"
        visible: pill.expanded

        Rectangle {
            id: card
            anchors.fill: parent
            color: Colors.background
            radius: 16
            clip: true   // keeps the blurred art from bleeding past the rounded corners

            // full-bleed album art backdrop, blurred so it reads as mood/color rather than a sharp image
            Image {
                id: bgArt
                anchors.fill: parent
                source: Media.artUrl
                visible: Media.artUrl !== ""
                fillMode: Image.PreserveAspectCrop
                smooth: true
                asynchronous: true

                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: 0.4
                    blurMax: 48
                }
            }

            // fallback flat color when there's no art at all
            Rectangle {
                anchors.fill: parent
                color: Colors.surface
                visible: Media.artUrl === ""
            }

            // darken gradient over the art so white text stays legible everywhere,
            // strongest at the bottom where the buttons sit
            Rectangle {
                anchors.fill: parent
                gradient: Gradient {
                    GradientStop { position: 0.0; color: "#8a000000" }
                    GradientStop { position: 0.55; color: "#70000000" }
                    GradientStop { position: 1.0; color: "#c0000000" }
                }
            }
            
            // wave sits as its own full-width layer behind everything in the Column,
            // declared before it so the Column's content (title, buttons, etc.) paints on top
            Wave {
                anchors.left: card.left
                anchors.right: card.right
                anchors.bottom: card.bottom
                height: 90   // tall enough to sit behind the button row — tweak to taste
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 14

                // icon + title/artist — no corner art anymore, art is the whole backdrop now
                Item {
                    width: parent.width
                    height: 44

                    Text {
                        id: appIcon
                        text: Media.appIcon
                        font.pixelSize: 22
                        color: Colors.accent
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Column {
                        anchors.left: appIcon.right
                        anchors.leftMargin: 12
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 4

                        Text {
                            color:Colors.text
                            font.bold: true
                            font.pixelSize: 16
                            width: parent.width
                            elide: Text.ElideRight
                            text: Media.title
                        }

                        Text {
                            color: Colors.accent
                            font.pixelSize: 12
                            width: parent.width
                            elide: Text.ElideRight
                            text: Media.artist + "  ·  " + Media.formatTime(Media.position) + " / " + Media.formatTime(Media.length)
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Qt.rgba(Colors.text_muted.r, Colors.text_muted.g, Colors.text_muted.b, 0.15)   // translucent white track reads better over art than flat gray

                    Rectangle {
                        width: parent.width * (Media.length > 0 ? Media.position / Media.length : 0)
                        height: parent.height
                        radius: 2
                        color: Colors.accent
                    }
                }

                // playback buttons — flat translucent circles instead of solid gray pills
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 20

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        color: Qt.rgba(Colors.text.r,Colors.text.g, Colors.text.b, 0.15)

                        Text {
                            anchors.centerIn: parent
                            text: "󰒮"
                            font.pixelSize: 18
                            color: Colors.text
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Media.previous()
                        }
                    }

                    Rectangle {
                        width: 48
                        height: 48
                        radius: 24
                        color: Colors.accent

                        Text {
                            anchors.centerIn: parent
                            text: Media.playing ? "󰏤" : "󰐊"
                            font.pixelSize: 20
                            color: Colors.text
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Media.togglePlay()
                        }
                    }

                    Rectangle {
                        width: 40
                        height: 40
                        radius: 20
                        color: Qt.rgba(Colors.text.r,Colors.text.g, Colors.text.b, 0.15)

                        Text {
                            anchors.centerIn: parent
                            text: "󰒭"
                            font.pixelSize: 18
                            color: Colors.text
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Media.next()
                        }
                    }
                }
            }
        }

        HyprlandFocusGrab {
            id: focusGrab
            windows: [popup]
            active: pill.expanded
            onCleared: pill.expanded = false
        }
    }
}
