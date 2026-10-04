import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import "./services" as Services

// The stash strip — adapted from Nebula's TuckTabs (GPL-3.0): a right-edge
// column of tabs, one per window parked on special:tuck. Rendered on every
// screen via the Variants/owns pattern but only SHOWN on the focused one,
// and never while that workspace is fullscreen or GameMode is on (same
// rules the bar follows). Click a tab to restore it, middle-click (or the
// card's ✕) to kill it, hover for the preview card.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        readonly property bool hidden: !!Hyprland.focusedMonitor?.activeWorkspace?.hasFullscreen
            || Services.GameMode.enabled
        readonly property bool owns: (Hyprland.focusedMonitor?.name ?? "") === modelData.name
            && Services.Tuck.tucked.length > 0
            && !win.hidden

        property string hoverAddr: ""
        readonly property var hovered: Services.Tuck.tucked.find(e => e.address === win.hoverAddr) ?? null

        visible: win.owns
        anchors { top: true; bottom: true; right: true }
        implicitWidth: 320
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "selah-tuck"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        // only the tabs and the hover card take input; the rest of the
        // 320px window passes clicks straight through to what's underneath
        mask: Region {
            Region { item: tabs }
            Region { item: card.visible ? card : none }
        }
        Item { id: none; width: 0; height: 0 }

        function iconFor(cls) {
            const e = DesktopEntries.heuristicLookup(cls)
            return Quickshell.iconPath(e?.icon ?? "", true)
        }
        function nameFor(cls) {
            return DesktopEntries.heuristicLookup(cls)?.name ?? (cls || "Window")
        }

        Timer {
            id: leave
            interval: 220
            onTriggered: if (!cardHover.hovered) win.hoverAddr = ""
        }

        Column {
            id: tabs
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            Repeater {
                model: Services.Tuck.tucked

                Rectangle {
                    id: tab
                    required property var modelData
                    readonly property bool hot: tabArea.containsMouse || win.hoverAddr === tab.modelData.address
                    anchors.right: parent.right
                    width: tab.hot ? 34 : 28
                    height: 66
                    topLeftRadius: 14
                    bottomLeftRadius: 14
                    color: tab.hot ? Services.Colors.surfaceAlt : Services.Colors.surface
                    border.width: 1
                    border.color: Services.Colors.low
                    Behavior on width {
                        SpringAnimation {
                            spring: Services.Motion.spatialFastSpring
                            damping: Services.Motion.spatialFastDamping
                        }
                    }

                    Column {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 1
                        spacing: 7

                        IconImage {
                            anchors.horizontalCenter: parent.horizontalCenter
                            implicitSize: 18
                            source: win.iconFor(tab.modelData.cls)
                            visible: source != ""
                        }
                        // no desktop entry for this class — fall back to its
                        // initial so the tab still says what it holds
                        Text {
                            anchors.horizontalCenter: parent.horizontalCenter
                            visible: win.iconFor(tab.modelData.cls) === ""
                            font.family: Services.Fonts.family
                            font.pixelSize: 13
                            font.bold: true
                            color: Services.Colors.textMuted
                            text: (tab.modelData.cls || "?").charAt(0).toUpperCase()
                        }
                        Rectangle {
                            anchors.horizontalCenter: parent.horizontalCenter
                            width: 3
                            height: 16
                            radius: 1.5
                            color: Services.Colors.low
                        }
                    }

                    MouseArea {
                        id: tabArea
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: {
                            if (containsMouse) {
                                leave.stop()
                                win.hoverAddr = tab.modelData.address
                            } else {
                                leave.restart()
                            }
                        }
                        onClicked: mouse => {
                            win.hoverAddr = ""
                            if (mouse.button === Qt.MiddleButton)
                                Services.Tuck.close(tab.modelData.address)
                            else
                                Services.Tuck.restore(tab.modelData.address)
                        }
                    }
                }
            }
        }

        Rectangle {
            id: card
            readonly property var entry: win.hovered
            visible: !!card.entry && win.owns
            width: 250
            height: cardCol.implicitHeight + 24
            x: win.width - 46 - width
            y: {
                const i = Services.Tuck.tucked.findIndex(e => e.address === win.hoverAddr)
                const ty = tabs.y + Math.max(0, i) * 74 + 33 - height / 2
                return Math.max(52, Math.min(win.height - height - 12, ty))
            }
            radius: 20
            color: Services.Colors.surface
            border.width: 1
            border.color: Services.Colors.low

            HoverHandler {
                id: cardHover
                onHoveredChanged: if (!hovered) leave.restart(); else leave.stop()
            }

            ColumnLayout {
                id: cardCol
                x: 12
                y: 12
                width: parent.width - 24
                spacing: 10

                RowLayout {
                    spacing: 10
                    Rectangle {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        radius: 12
                        color: Services.Colors.surfaceAlt
                        IconImage {
                            id: cardIcon
                            anchors.centerIn: parent
                            implicitSize: 22
                            source: card.entry ? win.iconFor(card.entry.cls) : ""
                            visible: source != ""
                        }
                        Text {
                            anchors.centerIn: parent
                            visible: !cardIcon.source
                            font.family: Services.Fonts.family
                            font.pixelSize: 15
                            font.bold: true
                            color: Services.Colors.textMuted
                            text: card.entry ? (card.entry.cls || "?").charAt(0).toUpperCase() : ""
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        Text {
                            Layout.fillWidth: true
                            font.family: Services.Fonts.family
                            font.pixelSize: 13
                            font.bold: true
                            color: Services.Colors.text
                            elide: Text.ElideRight
                            text: card.entry?.title ?? ""
                        }
                        Text {
                            Layout.fillWidth: true
                            font.family: Services.Fonts.family
                            font.pixelSize: 11
                            color: Services.Colors.textMuted
                            elide: Text.ElideRight
                            text: card.entry ? win.nameFor(card.entry.cls)
                                + ", tucked from workspace " + card.entry.from : ""
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        radius: 12
                        color: backArea.containsMouse
                             ? Qt.lighter(Services.Colors.accent, 1.08)
                             : Services.Colors.accent
                        Row {
                            anchors.centerIn: parent
                            spacing: 5
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Services.Fonts.family
                                font.pixelSize: 14
                                color: Services.Colors.background
                                text: "←"
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: Services.Fonts.family
                                font.pixelSize: 12
                                font.bold: true
                                color: Services.Colors.background
                                text: "Bring back"
                            }
                        }
                        MouseArea {
                            id: backArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const a = win.hoverAddr
                                win.hoverAddr = ""
                                Services.Tuck.restore(a)
                            }
                        }
                    }
                    Rectangle {
                        Layout.preferredWidth: 34
                        Layout.preferredHeight: 34
                        radius: 12
                        color: closeArea.containsMouse
                             ? Services.Colors.surfaceAlt : Services.Colors.surface
                        Text {
                            anchors.centerIn: parent
                            font.family: Services.Fonts.family
                            font.pixelSize: 14
                            color: Services.Colors.textMuted
                            text: "✕"
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                const a = win.hoverAddr
                                win.hoverAddr = ""
                                Services.Tuck.close(a)
                            }
                        }
                    }
                }
            }
        }
    }
}
