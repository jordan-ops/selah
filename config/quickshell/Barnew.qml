import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import QtQuick
import QtQuick.Effects
import Quickshell.Services.Notifications
import Quickshell.Io
import "./modules"
import "./services" as Services
// import "./services/Colors"
Variants {
    model: Quickshell.screens

    PanelWindow{
        id: toplevel
        required property var modelData
        screen: modelData
        WlrLayershell.layer: (pill.osdVisible || pill.notifVisible || Services.Launcher.open || Services.PowerMenu.open) ? WlrLayer.Overlay : WlrLayer.Top
        anchors{ top: true; left:true; right:true}
        implicitHeight: 35
        color:"transparent"
        WlrLayershell.keyboardFocus: Services.Launcher.open ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle{
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            height: pill.effectiveHover ? 35 : 30
            bottomLeftRadius: height/2
	    bottomRightRadius: height/2
            // color:"#282828"
            color: Services.Colors.background

            property bool osdVisible: false
            property string osdType: "volume"
            property real osdValue: 0
            property bool effectiveHover: true  // always expanded now

            property bool notifVisible: false
            property var currentNotification: null

            width: Services.Launcher.open ? 220
                 : (osdVisible ? 220
                 : (notifVisible ? 420
                 : (Services.PowerMenu.open ? 200
                 : 620)))

            Behavior on width{
                NumberAnimation{ duration: 250; easing.type: Easing.OutCubic}
            }

            function showOsd(type, value) {
                pill.osdType = type
                pill.osdValue = value
                pill.osdVisible = true
                osdTimer.restart()
            }

            Timer {
                id: osdTimer
                interval: 1800
                onTriggered: pill.osdVisible = false
            }

            // same shape as showOsd()/osdTimer above — morph in, hold, morph back
            function showNotification(notification) {
                pill.currentNotification = notification
                pill.notifVisible = true
                notifTimer.restart()
            }

            Timer {
                id: notifTimer
                interval: 4000
                onTriggered: pill.notifVisible = false
            }

            Connections {
                target: Services.Volume
                function onVolumeChanged() { pill.showOsd("volume", Services.Volume.volume) }
                function onMutedChanged() { pill.showOsd("volume", Services.Volume.volume) }
            }

            Connections {
                target: Services.Brightness
                function onLevelChanged() { pill.showOsd("brightness", Services.Brightness.level) }
            }

            Connections {
                target: Services.Notifications
                function onNewNotification(notification) { pill.showNotification(notification) }
            }

            // drives keyboard focus into the search field the moment the launcher opens,
            // and clears the field the moment it closes — same idea as osdTimer resetting osdVisible
            Connections {
                target: Services.Launcher
                function onOpenChanged() {
                    if (Services.Launcher.open) {
                        searchField.forceActiveFocus()
                    } else {
                        searchField.text = ""
                    }
                }
            }

            Item {
                id: normalContent
                anchors.fill: parent
                opacity: (pill.osdVisible || pill.notifVisible || Services.Launcher.open || Services.PowerMenu.open) ? 0 : 1
                Behavior on opacity { NumberAnimation { duration: 120 } }

                // clock + media pill grouped together on the left, same idea as a
                // Waybar modules-left array: "clock, custom/media" listed side by side
                Row {
                    id: leftGroup
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Clock {
                        id: clockItem
                    }

                    MediaPill {
                        id: mediaPill
                        anchors.verticalCenter: parent.verticalCenter
                        // hasPlayer covers playing OR paused; only a closed app hides it
                        visible: Services.Media.hasPlayer
                    }
                }

                // workspaces sit dead center of the bar, independent of how wide
                // the left/right groups are — like Waybar's modules-center array
                Workspaces {
                    anchors.centerIn: parent
                }

                Row{
                    id: rightGroup
                    anchors.right:parent.right
                    anchors.rightMargin:12
                    anchors.verticalCenter:parent.verticalCenter
                    spacing: 10
                    opacity: pill.effectiveHover ? 1 : 0
                    Behavior on opacity{ NumberAnimation{duration: 150}}

                    // Screen recording indicator — shows a plain dot icon
                    // when idle, expands to show the elapsed timer in red
                    // while actively recording. Always visible (unlike the
                    // update badge) since it's a toggle, not just a count.
                    Rectangle {
                        id: recIcon
                        height: 26
                        width: recRow.width + 16
                        radius: 13
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Services.ScreenRecording.recording
                        color: Qt.rgba(0.88, 0.38, 0.38, 0.18)

                        Row {
                            id: recRow
                            anchors.centerIn: parent
                            spacing: 4
                            Text {
                                text: "●"
                                font.pixelSize: Services.ScreenRecording.recording ? 9 : 11
                                color: Services.ScreenRecording.recording ? "#e06060" : Services.Colors.text
                            }
                            Text {
                                visible: Services.ScreenRecording.recording
                                text: Services.ScreenRecording.elapsedDisplay
                                font.pixelSize: 11
                                color: "#e06060"
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Services.ScreenRecording.toggle()
                        }
                    }

                    // Update badge — hidden entirely at 0 pending (Row
                    // skips invisible children in layout, same reasoning
                    // as MediaPill hiding when hasPlayer is false).
                    Rectangle {
                        id: updatesIcon
                        width: 26; height: 26; radius: 13
                        color: Services.Colors.surface
                        anchors.verticalCenter: parent.verticalCenter
                        visible: Services.Updates.count > 0

                        Text {
                            anchors.centerIn: parent
                            text: "󰚰"
                            font.pixelSize: 13
                            color: Services.Colors.accent
                        }

                        Rectangle {
                            width: 14; height: 14; radius: 7
                            color: Services.Colors.accent
                            anchors { top: parent.top; right: parent.right; topMargin: -2; rightMargin: -2 }
                            Text {
                                anchors.centerIn: parent
                                text: Services.Updates.count > 9 ? "9+" : Services.Updates.count
                                font.pixelSize: 8
                                font.bold: true
                                color: Services.Colors.background
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Services.Updates.toggle()
                        }
                    }
                    
                    // battery/network/power grouped into one pill — clicking anywhere
                    // in it opens the control center. the power icon keeps its own
                    // MouseArea on top, so clicking IT specifically still opens the
                    // power menu directly instead
                    Rectangle {
                        id: statusGroup
                        width: statusRow.width + 20
                        height: 26
                        radius: 13
                        color: Services.Colors.surface
                        anchors.verticalCenter: parent.verticalCenter

                        MouseArea {
                            anchors.fill: parent
                            onClicked: Services.ControlCenter.toggle()
                        }

                        Row {
                            id: statusRow
                            anchors.centerIn: parent
                            spacing: 10

                            BatteryIcon{}
                            Network{}

                            Text {
                                text: "⏻"
                                color: Services.Colors.text
                                font.pixelSize: 14
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter

                                // MouseArea {
                                //     anchors.fill: parent
                                //     onClicked: Services.PowerMenu.open = !Services.PowerMenu.open
                                // }
                            }
                        }
                    }
                }
            }

            Row {
                id: osdContent
                anchors.centerIn: parent
                spacing: 10
                opacity: pill.osdVisible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    color: Services.Colors.text
                    font.pixelSize: 16
                    text: {
                        if (pill.osdType === "volume") return Services.Volume.muted ? "󰝟" : "󰕾"
                        return "󰃟"
                    }
                }

                Rectangle {
                    width: 140
                    height: 4
                    radius: 2
                    color: Services.Colors.surface
                    anchors.verticalCenter: parent.verticalCenter

                    Rectangle {
                        width: parent.width * pill.osdValue
                        height: parent.height
                        radius: 2
                        color: Services.Colors.accent
                    }
                }
            }

            // pill morphs to show the latest notification for a few seconds, then
            // fades back to normalContent — identical mechanism to osdContent above,
            // just triggered by Services.Notifications instead of Volume/Brightness
            Row {
                id: notificationContent
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 10
                opacity: pill.notifVisible ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 16
                    color: {
                        if (!pill.currentNotification) return Services.Colors.text
                        if (pill.currentNotification.urgency === NotificationUrgency.Critical) return Services.Colors.critical
                        if (pill.currentNotification.urgency === NotificationUrgency.Low) return Services.Colors.low
                        return Services.Colors.accent
                    }
                    text: "󰂚"
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    font.pixelSize: 13
                    width: parent.width - 30
                    elide: Text.ElideRight
                    color: Services.Colors.text
                    text: {
                        if (!pill.currentNotification) return ""
                        const n = pill.currentNotification
                        return n.body ? (n.summary + "  —  " + n.body) : n.summary
                    }
                }
            }

            // the REAL search input now lives here, in the same window as toplevel —
            // this is the piece that actually receives the keyboard focus we grab above
            Row {
                id: launcherContent
                anchors.centerIn: parent
                width: parent.width - 24
                spacing: 8
                opacity: Services.Launcher.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                Text {
                    text: "󰍉"
                    color: Services.Colors.text
                    font.pixelSize: 15
                    anchors.verticalCenter: parent.verticalCenter
                }

                TextInput {
                    id: searchField
                    width: parent.width - 30
                    color: Services.Colors.text
                    font.pixelSize: 14
                    anchors.verticalCenter: parent.verticalCenter
                    onTextChanged: Services.Launcher.query = text

                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_Escape) {
                            Services.Launcher.closeLauncher()
                            event.accepted = true
                        } else if (event.key === Qt.Key_Down) {
                            Services.Launcher.moveSelection(1)
                            resultsList.positionViewAtIndex(Services.Launcher.selectedIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Up) {
                            Services.Launcher.moveSelection(-1)
                            resultsList.positionViewAtIndex(Services.Launcher.selectedIndex, ListView.Contain)
                            event.accepted = true
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            Services.Launcher.launchSelected()
                            event.accepted = true
                        }
                    }
                }
            }

            // power menu morphs into the pill exactly like osdContent/notificationContent above —
            // no separate popup window, just another mutually-exclusive Row toggled by opacity
            Row {
                id: powerContent
                anchors.centerIn: parent
                spacing: 10
                opacity: Services.PowerMenu.open ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 120 } }

                Repeater {
                    model: Services.PowerMenu.actions
                    Rectangle {
                        width: 36
                        height: 36
                        radius: 18
                        color: itemArea.containsMouse ? Services.Colors.surface : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.icon
                            color: Services.Colors.text
                            font.pixelSize: 16
                        }

                        MouseArea {
                            id: itemArea
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                powerProcess.command = modelData.command
                                powerProcess.running = true
                                Services.PowerMenu.open = false
                            }
                        }
                    }
                }
            }

        }

        // full media card — same content that used to live in the separate MediaBar.qml
        // window, now anchored under wherever mediaPill actually sits (it moves with the
        // clock group, so we ask Qt for its real position via mapToItem instead of a
        // hardcoded offset)
        PopupWindow {
            id: mediaPopup
            anchor.window: toplevel
            // pill.x, leftGroup.x, mediaPill.x are all plain Item positions along the
            // same left-to-right chain — summing them tracks reactively, unlike
            // mapFromItem() which the Quickshell docs say does NOT update reactively
            anchor.rect.x: pill.x + leftGroup.x + mediaPill.x
            anchor.rect.y: 50
            implicitWidth: 480
            implicitHeight: 220
            color: "transparent"
            visible: mediaPill.expanded

            Rectangle {
                id: mediaCard
                anchors.fill: parent
                color: Services.Colors.background
                radius: 16
                clip: true

                Image {
                    id: bgArt
                    anchors.fill: parent
                    source: Services.Media.artUrl
                    visible: Services.Media.artUrl !== ""
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

                Rectangle {
                    anchors.fill: parent
                    color: Services.Colors.surface
                    visible: Services.Media.artUrl === ""
                }

                Rectangle {
                    anchors.fill: parent
                    gradient: Gradient {
                        GradientStop { position: 0.0; color: "#8a000000" }
                        GradientStop { position: 0.55; color: "#70000000" }
                        GradientStop { position: 1.0; color: "#c0000000" }
                    }
                }

                Wave {
                    anchors.left: mediaCard.left
                    anchors.right: mediaCard.right
                    anchors.bottom: mediaCard.bottom
                    height: 90
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 14

                    Item {
                        width: parent.width
                        height: 44

                        Text {
                            id: appIconText
                            text: Services.Media.appIcon
                            font.pixelSize: 22
                            color: Services.Colors.accent
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            anchors.left: appIconText.right
                            anchors.leftMargin: 12
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            Text {
                                color: Services.Colors.text
                                font.bold: true
                                font.pixelSize: 16
                                width: parent.width
                                elide: Text.ElideRight
                                text: Services.Media.title
                            }

                            Text {
                                color: Services.Colors.accent
                                font.pixelSize: 12
                                width: parent.width
                                elide: Text.ElideRight
                                text: Services.Media.artist + "  ·  " + Services.Media.formatTime(Services.Media.position) + " / " + Services.Media.formatTime(Services.Media.length)
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: 4
                        radius: 2
                        color: Qt.rgba(Services.Colors.text_muted.r, Services.Colors.text_muted.g, Services.Colors.text_muted.b, 0.15)

                        Rectangle {
                            width: parent.width * (Services.Media.length > 0 ? Services.Media.position / Services.Media.length : 0)
                            height: parent.height
                            radius: 2
                            color: Services.Colors.accent
                        }
                    }

                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 20

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.15)

                            Text {
                                anchors.centerIn: parent
                                text: "󰒮"
                                font.pixelSize: 18
                                color: Services.Colors.text
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: Services.Media.previous()
                            }
                        }

                        Rectangle {
                            width: 48
                            height: 48
                            radius: 24
                            color: Services.Colors.accent

                            Text {
                                anchors.centerIn: parent
                                text: Services.Media.playing ? "󰏤" : "󰐊"
                                font.pixelSize: 20
                                color: Services.Colors.text
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: Services.Media.togglePlay()
                            }
                        }

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.15)

                            Text {
                                anchors.centerIn: parent
                                text: "󰒭"
                                font.pixelSize: 18
                                color: Services.Colors.text
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: Services.Media.next()
                            }
                        }
                    }
                }
            }

            HyprlandFocusGrab {
                windows: [mediaPopup]
                active: mediaPill.expanded
                onCleared: mediaPill.expanded = false
            }
        }

        // results-only dropdown — no text input in here anymore, just a mouse-clickable list,
        // same role as a Waybar tooltip: shows info, takes no keyboard input of its own
        PopupWindow {
            id: launcherPopup
            anchor.window: toplevel
            anchor.rect.x: (toplevel.width / 2) - (implicitWidth / 2)
            anchor.rect.y: 50
            implicitWidth: 420
            implicitHeight: 400
            color: "transparent"
            visible: Services.Launcher.open

            Rectangle {
                anchors.fill: parent
                radius: 16
                color: Services.Colors.background

                ListView {
                    id: resultsList
                    anchors.fill: parent
                    anchors.margins: 12
                    clip: true
                    model: Services.Launcher.results
                    currentIndex: Services.Launcher.selectedIndex

                    delegate: Rectangle {
                        width: resultsList.width
                        height: 44
                        radius: 8
                        color: index === Services.Launcher.selectedIndex ? Services.Colors.surface : "transparent"

                        Row {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 10

                            IconImage {
                                implicitSize: 24
                                source: modelData.icon !== "" ? Quickshell.iconPath(modelData.icon, true) : ""
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            Text {
                                color: Services.Colors.text
                                font.pixelSize: 13
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                modelData.execute()
                                Services.Launcher.closeLauncher()
                            }
                        }
                    }
                }
            }
        }

        PopupWindow {
            id: wallpaperPopup
            anchor.window: toplevel
            anchor.rect.x: (toplevel.width / 2) - (implicitWidth / 2)
            anchor.rect.y: 50
            implicitWidth: 900
            implicitHeight: 220
            color: "transparent"
            visible: Services.Wallpapers.open

            // Every other popup wraps its content in an anchored Item —
            // this one was missing that, which is almost certainly why it
            // rendered blank: WallpaperPicker never got told to fill the
            // window.
            Item {
                anchors.centerIn: parent
                width: 900
                height: 220
                WallpaperPicker {}
            }
        }

        PopupWindow {
    id: themePopup
    anchor.window: toplevel
    anchor.rect.x: (toplevel.width / 2) - (implicitWidth / 2)
    anchor.rect.y: 50
    implicitWidth: 600
    implicitHeight: 420
    color: "transparent"
    visible: Services.Themes.open

    ThemePicker {}
}

        PopupWindow {
            id: controlCenterPopup
            anchor.window: toplevel
            anchor.rect.x: (toplevel.width / 2) - (implicitWidth / 2)
            anchor.rect.y: 50
            // Fixed size, always — a PopupWindow must never have its
            // implicitWidth/implicitHeight animated directly (breaks its
            // anchor.rect positioning). The `sizer` Item below is what
            // actually grows/shrinks; this window just holds still.
            // 600 matches ControlCenterPanel.qml's width for the 3x2 grid.
            implicitWidth: 600
            implicitHeight: 380
            color: "transparent"

            // Animate-then-hide, same pattern as ClipboardPopup.qml: the
            // window stays mounted and visible until the shrink animation
            // below finishes, instead of vanishing the instant `open` flips
            // false. Fixes the panel snapping shut.
            property bool windowVisible: false
            visible: windowVisible

            Connections {
                target: Services.ControlCenter
                function onOpenChanged() {
                    if (Services.ControlCenter.open) {
                        closeTimer.stop()
                        controlCenterPopup.windowVisible = true
                    } else {
                        closeTimer.restart()
                    }
                }
            }

            Timer {
                id: closeTimer
                // matches sizer's Behavior duration below + a small buffer
                interval: 270
                onTriggered: {
                    if (!Services.ControlCenter.open)
                        controlCenterPopup.windowVisible = false
                }
            }

            Item {
                id: sizer
                anchors.centerIn: parent
                clip: true

                width:  Services.ControlCenter.open ? 600 : 0
                height: Services.ControlCenter.open ? 380 : 0

                Behavior on width  { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

                ControlCenterPanel {
                    anchors.centerIn: parent
                }
            }
        }

        // Advanced side panel — docks to the right of controlCenterPopup.
        // Same animate-then-hide pattern, driven by advancedPanel instead
        // of open. Separate window because it needs real room for
        // pair/trust/forget controls that don't fit in a tile-sized popover.
        PopupWindow {
            id: controlCenterAdvancedPopup
            anchor.window: toplevel
            anchor.rect.x: controlCenterPopup.anchor.rect.x + 600 + 12
            anchor.rect.y: 50
            implicitWidth: 260
            implicitHeight: 380
            color: "transparent"

            property bool windowVisible: false
            visible: windowVisible

            Connections {
                target: Services.ControlCenter
                function onAdvancedPanelChanged() {
                    if (Services.ControlCenter.advancedPanel !== "") {
                        advClose.stop()
                        controlCenterAdvancedPopup.windowVisible = true
                    } else {
                        advClose.restart()
                    }
                }
            }

            Timer {
                id: advClose
                interval: 270
                onTriggered: {
                    if (Services.ControlCenter.advancedPanel === "")
                        controlCenterAdvancedPopup.windowVisible = false
                }
            }

            Item {
                id: advSizer
                anchors.centerIn: parent
                clip: true

                width:  Services.ControlCenter.advancedPanel !== "" ? 260 : 0
                height: Services.ControlCenter.advancedPanel !== "" ? 380 : 0

                Behavior on width  { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

                ControlCenterAdvanced {
                    anchors.centerIn: parent
                }
            }
        }

        // Clock card — anchored under the actual clock position, not
        // guessed: pill is horizontally centered in toplevel, and Clock.qml
        // sits leftMargin 12 inside leftGroup, which is leftMargin 12
        // inside pill itself. Reactive, so it tracks if pill.width ever
        // changes (though in practice the clock's hidden during
        // OSD/launcher/notif states anyway, when pill briefly narrows).
        PopupWindow {
            id: clockPopup
            anchor.window: toplevel
            anchor.rect.x: (toplevel.width - pill.width) / 2 + 12
            anchor.rect.y: 40
            implicitWidth: 300
            implicitHeight: 520
            color: "transparent"

            property bool windowVisible: false
            visible: windowVisible

            Connections {
                target: Services.ClockCard
                function onOpenChanged() {
                    if (Services.ClockCard.open) {
                        clockCloseTimer.stop()
                        clockPopup.windowVisible = true
                    } else {
                        clockCloseTimer.restart()
                    }
                }
            }

            Timer {
                id: clockCloseTimer
                interval: 270
                onTriggered: {
                    if (!Services.ClockCard.open)
                        clockPopup.windowVisible = false
                }
            }

            Item {
                id: clockSizer
                anchors.centerIn: parent
                clip: true

                width:  Services.ClockCard.open ? 300 : 0
                height: Services.ClockCard.open ? 520 : 0

                Behavior on width  { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

                ClockCardPopup {
                    anchors.centerIn: parent
                }
            }
        }

        // Recording popup — first child in rightGroup, so its x is simply
        // rightGroup's left edge.
        PopupWindow {
            id: recordingPopup
            anchor.window: toplevel
            anchor.rect.x: (toplevel.width + pill.width) / 2 - 12 - rightGroup.width
            anchor.rect.y: 40
            implicitWidth: 260
            implicitHeight: 300
            color: "transparent"

            property bool windowVisible: false
            visible: windowVisible

            Connections {
                target: Services.ScreenRecording
                function onOpenChanged() {
                    if (Services.ScreenRecording.open) {
                        recCloseTimer.stop()
                        recordingPopup.windowVisible = true
                    } else {
                        recCloseTimer.restart()
                    }
                }
            }

            Timer {
                id: recCloseTimer
                interval: 270
                onTriggered: {
                    if (!Services.ScreenRecording.open)
                        recordingPopup.windowVisible = false
                }
            }

            Item {
                id: recSizer
                anchors.centerIn: parent
                clip: true

                width:  Services.ScreenRecording.open ? 260 : 0
                height: Services.ScreenRecording.open ? 300 : 0

                Behavior on width  { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

                ScreenRecordingPopup {
                    anchors.centerIn: parent
                }
            }
        }

        HyprlandFocusGrab {
            windows: [recordingPopup]
            active: Services.ScreenRecording.open
            onCleared: Services.ScreenRecording.close()
        }

        // Updates popup — recIcon is the first child of rightGroup, but
        // only occupies space when actually visible (hidden entirely when
        // not recording, same as MediaPill). Account for both cases.
        PopupWindow {
            id: updatesPopup
            anchor.window: toplevel
            anchor.rect.x: (toplevel.width + pill.width) / 2 - 12 - rightGroup.width
                + (recIcon.visible ? recIcon.width + 10 : 0)
            anchor.rect.y: 40
            implicitWidth: 280
            implicitHeight: 380
            color: "transparent"

            property bool windowVisible: false
            visible: windowVisible

            Connections {
                target: Services.Updates
                function onOpenChanged() {
                    if (Services.Updates.open) {
                        updatesCloseTimer.stop()
                        updatesPopup.windowVisible = true
                    } else {
                        updatesCloseTimer.restart()
                    }
                }
            }

            Timer {
                id: updatesCloseTimer
                interval: 270
                onTriggered: {
                    if (!Services.Updates.open)
                        updatesPopup.windowVisible = false
                }
            }

            Item {
                id: updatesSizer
                anchors.centerIn: parent
                clip: true

                width:  Services.Updates.open ? 280 : 0
                height: Services.Updates.open ? 380 : 0

                Behavior on width  { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }
                Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.InOutCubic } }

                UpdatesPopup {
                    anchors.centerIn: parent
                }
            }
        }

        HyprlandFocusGrab {
            windows: [updatesPopup]
            active: Services.Updates.open
            onCleared: Services.Updates.close()
        }

        HyprlandFocusGrab {
            windows: [clockPopup]
            active: Services.ClockCard.open
            onCleared: Services.ClockCard.close()
        }

        HyprlandFocusGrab {
            windows: [controlCenterPopup, controlCenterAdvancedPopup]
            active: Services.ControlCenter.open
            onCleared: Services.ControlCenter.close()
        }

        // power menu no longer has its own PopupWindow — it morphs inside the pill
        // (see powerContent above), same pattern as OSD/notification. We still need
        // a Process to actually run the shutdown/reboot/logout command, and a
        // focus grab so clicking outside the bar closes the menu.
        Process {
            id: powerProcess
        }

        HyprlandFocusGrab {
            windows: [toplevel]
            active: Services.PowerMenu.open
            onCleared: Services.PowerMenu.open = false
        }
    }
}
