// The control center panel — same idea as Waybar's modules-left /
// modules-right split: two Columns side by side with a thin Rectangle
// standing in for the "|".

import "./modules"
import "./services" as Services
import QtQuick
import Quickshell
import Quickshell.Networking
import Quickshell.Services.Notifications
import Quickshell.Widgets

// Visual language matches the settings window and the bar revamp: solid
// accent = ON (same as a selected choice chip), surface = idle, springs
// on every interactive press, BatteryRing as the hero status glyph so the
// bar and this panel never disagree about what the battery looks like.
Rectangle {
    // NOTE: Bar.qml's modes table ("controlcenter" size entry) needs to
    // match this — 760 / 440 (440 grew from 380 when the toggles went
    // 2 rows to 3). The advanced side popup deliberately keeps ITS 380:
    // it sizes from ControlCenterAdvanced's own card, not from the pill.
    // 760 (was 600) is what gives the notification column room: the left
    // column is a fixed 340, so the notif column went 212 → 372 — the old
    // strip was too narrow to read a notification body in.
    // Right-clicking Audio/Network/Bluetooth opens the advanced window
    // directly — one click to the real controls instead of two.

    id: root

    width: 760
    height: 440
    radius: 18
    // panel (alpha'd) over the pill's own panel fill: two layers, so the
    // control center reads slightly more opaque than the bare bar at
    // transparency > 0 — never a fully solid slab either way. At 0 both
    // are plain `background`, pixel-identical to before.
    color: Services.Colors.panel

    // Mirror Services.Notifications.history into grpModel as ONE ROW PER
    // APP (a group's slot follows its newest member, so a fresh message
    // bumps that group to the top). The service reassigns the whole array
    // on arrival, which a ListView reads as a model RESET — delegates get
    // destroyed and recreated at their final positions, so add/displaced/
    // remove transitions never run (verified against a recording: cards
    // popped in with no drop). Row inserts/removes/moves fire the real
    // signals and the bounce plays. Rows hold no notifications: each
    // delegate reads notifsFor(name) in a binding, so any history change
    // refreshes a group's contents without disturbing its row slot.
    function syncHistory() {
        const keys = Services.Notifications.groupNames()
        // groups that lost every member (dismissed / Clear all):
        // remove transition fades each out in place
        for (let i = grpModel.count - 1; i >= 0; i--)
            if (keys.indexOf(grpModel.get(i).name) === -1)
                grpModel.remove(i)
        // align from the top: a new group inserts as row i (add
        // transition drops it in with the bounce spring), an existing
        // group whose newest member jumped the queue slides into place
        // (displaced spring), rows below displace-spring
        for (let i = 0; i < keys.length; i++) {
            let j = -1
            for (let k = i; k < grpModel.count; k++)
                if (grpModel.get(k).name === keys[i]) { j = k; break }
            if (j === i) continue
            if (j === -1) grpModel.insert(i, { "name": keys[i], "expanded": true })
            else grpModel.move(j, i, 1)
        }
        while (grpModel.count > keys.length) grpModel.remove(grpModel.count - 1)
    }

    // If the whole panel closes (Bar.qml's animate-then-hide), close the
    // advanced side window too — otherwise it'd still be "open"
    // underneath next time the panel reappears.
    Connections {
        function onOpenChanged() {
            if (!Services.ControlCenter.open)
                Services.ControlCenter.closeAdvanced();

        }

        target: Services.ControlCenter
    }

    Row {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 16

        // ---------------- LEFT: header + status + toggles + sliders ----------------
        Column {
            id: leftColumn

            width: 340
            height: parent.height
            spacing: 12

            // Header — title left, settings gear right. The gear jumps
            // straight into the settings app (super+; does the same).
            Row {
                id: ccHeader

                width: parent.width
                height: 26
                spacing: 8

                Text {
                    font.family: Services.Fonts.family
                    id: ccTitle

                    text: "Control center"
                    color: Services.Colors.text
                    font.pixelSize: 15
                    font.bold: true
                    height: 26
                    verticalAlignment: Text.AlignVCenter
                }

                Item {
                    width: Math.max(4, parent.width - ccTitle.width - ccGear.width - parent.spacing * 2)
                    height: 1
                }

                Text {
                    font.family: Services.Fonts.family
                    id: ccGear

                    text: "󰒓"
                    font.pixelSize: 14
                    color: Services.Colors.textMuted
                    height: 26
                    verticalAlignment: Text.AlignVCenter

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.SettingsApp.toggle()
                    }

                }

            }

            // Hero status strip — the same BatteryRing the bar shows, plus
            // percent + charge state, network (click = advanced network),
            // and power. Replaces the old tiny BatteryIcon/Network pill.
            Rectangle {
                id: statusGroupCC

                width: parent.width
                height: 44
                radius: 14
                color: Services.Colors.surface

                BatteryRing {
                    id: ccRing

                    clickOpensCC: false
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                }

                Column {
                    id: battCol

                    // no battery on this machine: ring collapses to the
                    // network glyph and this column vanishes — the divider
                    // below re-anchors straight to the ring so the net icon
                    // doesn't float in dead space
                    visible: Services.Battery.hasBattery
                    anchors.left: ccRing.right
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1

                    Text {
                        font.family: Services.Fonts.family
                        text: Services.Battery.percent + "%"
                        color: Services.Colors.text
                        font.pixelSize: 13
                        font.bold: true
                    }

                    Text {
                        font.family: Services.Fonts.family
                        text: Services.Battery.charging ? "Charging" : "On battery"
                        color: Services.Colors.textMuted
                        font.pixelSize: 10
                    }

                }

                Rectangle {
                    id: statusDivider

                    anchors.left: Services.Battery.hasBattery ? battCol.right
                                                              : ccRing.right
                    anchors.leftMargin: Services.Battery.hasBattery ? 14 : 8
                    anchors.verticalCenter: parent.verticalCenter
                    width: 1
                    height: 26
                    color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.15)
                }

                Text {
                    font.family: Services.Fonts.family
                    id: netIcon

                    text: Services.Network.glyph
                    font.pixelSize: 14
                    color: Services.Network.connected ? Services.Colors.text : Services.Colors.textMuted
                    anchors.left: statusDivider.right
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.ControlCenter.openAdvanced("network")
                    }

                }

                Text {
                    font.family: Services.Fonts.family
                    id: netName

                    text: Services.Network.connected ? Services.Network.name : "Offline"
                    font.pixelSize: 12
                    color: Services.Colors.text
                    elide: Text.ElideRight
                    anchors.left: netIcon.right
                    anchors.leftMargin: 6
                    anchors.right: ccPower.left
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.ControlCenter.openAdvanced("network")
                    }

                }

                Text {
                    font.family: Services.Fonts.family
                    id: ccPower

                    text: "⏻"
                    font.pixelSize: 14
                    color: Services.Colors.text
                    anchors.right: parent.right
                    anchors.rightMargin: 14
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.PowerMenu.open = !Services.PowerMenu.open
                    }

                }

            }

            // 3x3 bento grid of tiles — nine cells, nine used. Left click
            // toggles; right click on Network/Bluetooth/Audio opens the
            // matching advanced window (one click to the real controls).
            Grid {
                id: toggleGrid

                columns: 3
                spacing: 10

                SquareToggle {
                    id: networkTile

                    icon: Services.Network.glyph
                    label: "Network"
                    active: Services.Network.connected
                    onToggled: Services.Network.toggleWifi()
                    onRightClicked: Services.ControlCenter.openAdvanced("network")
                }

                SquareToggle {
                    id: bluetoothTile

                    icon: "󰂯"
                    label: "Bluetooth"
                    active: Services.Bluetooth.powered
                    onToggled: Services.Bluetooth.toggle()
                    onRightClicked: Services.ControlCenter.openAdvanced("bluetooth")
                }

                SquareToggle {
                    icon: "󰂛"
                    label: "DND"
                    active: Services.DoNotDisturb.enabled
                    onToggled: Services.DoNotDisturb.toggle()
                }

                SquareToggle {
                    icon: "󰖔"
                    label: "Night Light"
                    active: Services.NightLight.active
                    onToggled: Services.NightLight.toggle()
                }

                // Left click mutes/unmutes, right click opens the output
                // device picker — the on-click / on-click-right split,
                // both living on one tile.
                SquareToggle {
                    id: audioTile

                    icon: Services.Volume.muted ? "󰝟" : "󰕾"
                    label: "Audio"
                    active: !Services.Volume.muted
                    onToggled: Services.Volume.toggleMute()
                    onRightClicked: Services.ControlCenter.openAdvanced("audio")
                }

                // Left click OPENS the recording popup rather than starting a
                // recording straight from a tap. The popup is where capture
                // target (screen / window / region) and mic/system audio are
                // chosen, plus Start/Stop/Discard — none of which a bare
                // toggle could offer, so a one-tap start locked you into the
                // current defaults with no way to see or change them.
                //
                // The control center is closed on the way out so the popup
                // isn't fighting a full panel for the same corner of screen;
                // Services.ScreenRecording is shared, so its state carries
                // over and the bar's rec chip still shows the elapsed time.
                //
                // Right click is kept as a deliberate start/stop shortcut for
                // when you genuinely want "hit it and record, defaults".
                SquareToggle {
                    id: recordTile

                    icon: "⏺"
                    label: Services.ScreenRecording.recording ? Services.ScreenRecording.elapsedDisplay : Services.ScreenRecording.starting ? "Starting…" : "Record"
                    active: Services.ScreenRecording.recording || Services.ScreenRecording.starting
                    onToggled: {
                        Services.ControlCenter.close()
                        Services.ScreenRecording.open = true
                    }
                    onRightClicked: Services.ScreenRecording.recording
                        ? Services.ScreenRecording.stopRecording()
                        : Services.ScreenRecording.startRecording()
                }

                // Game mode: hyprland animations/blur/shadows off, gaps
                // and rounding to zero, DND on, quickshell animations
                // paused — one flag (services/GameMode.qml explains the
                // hyprctl reload restore path). Right click restores the
                // config straight away.
                SquareToggle {
                    id: gameModeTile

                    icon: "󰊴"
                    label: "Game Mode"
                    active: Services.GameMode.enabled
                    onToggled: Services.GameMode.toggle()
                    onRightClicked: Services.GameMode.disable()
                }

                // Keep awake: screensaver refuses to launch + a Wayland
                // idle-inhibit surface covers every other idle consumer.
                // Session-only by design (services/KeepAwake.qml) — a
                // restart always comes back with idle protection armed.
                SquareToggle {
                    id: keepAwakeTile

                    icon: "󰃖"
                    label: "Keep Awake"
                    active: Services.KeepAwake.active
                    onToggled: Services.KeepAwake.toggle()
                }

                // Screen saver on/off — omarchy's screensaver-off flag,
                // the file `omarchy toggle screensaver` writes. Off also
                // kills a running saver on the spot: every pipes.sh
                // terminal is animation CPU this tile exists to silence.
                // Right click runs one NOW regardless of the flag (the
                // launcher's `force`, same as System > Screensaver).
                SquareToggle {
                    icon: "\u{F0904}"   // nf-md-power_sleep
                    label: "Screen Saver"
                    active: Services.Screensaver.enabled
                    onToggled: Services.Screensaver.toggle()
                    onRightClicked: Services.Screensaver.force()
                }

            }

            // Brightness + volume sliders, same visual language as the
            // bar's OSD bar.
            QSSlider {
                width: parent.width
                icon: "󰃟"
                value: Services.Brightness.level
                onMoved: (v) => {
                    return Services.Brightness.setLevel(v);
                }
            }

            QSSlider {
                width: parent.width
                icon: Services.Volume.muted ? "󰝟" : "󰕾"
                value: Services.Volume.volume
                onMoved: (v) => {
                    return Services.Volume.setVolume(v);
                }
            }

        }

        // ---------------- SEPARATOR ----------------
        Rectangle {
            width: 1
            height: parent.height
            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.15)
        }

        // ---------------- RIGHT: notification history ----------------
        Column {
            id: rightColumn

            width: parent.width - leftColumn.width - 1 - parent.spacing * 2
            height: parent.height
            spacing: 10

            // system vitals — CPU/RAM sparklines + live net rates
            // (Services.Vitals samples /proc every 2s, 10min buffers)
            Rectangle {
                id: vitalsCard
                width: parent.width
                height: 100
                radius: 12
                color: Services.Colors.surface
                border.color: Services.Colors.low
                border.width: 1

                Column {
                    anchors.fill: parent
                    anchors.margins: 10
                    spacing: 6

                    Item {
                        width: parent.width
                        height: 16

                        Text {
                            font.family: Services.Fonts.family
                            text: "System"
                            font.pixelSize: 12
                            font.bold: true
                            color: Services.Colors.text
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            font.family: Services.Fonts.family
                            id: cpuLabel
                            anchors.right: ramLabel.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: "CPU " + Math.round(Services.Vitals.cpu) + "%"
                            font.pixelSize: 10
                            font.bold: true
                            color: Services.Colors.accent
                        }
                        Text {
                            font.family: Services.Fonts.family
                            id: ramLabel
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "RAM " + Math.round(Services.Vitals.mem) + "%"
                            font.pixelSize: 10
                            font.bold: true
                            color: Services.Colors.textMuted
                        }
                    }

                    Canvas {
                        id: vitGraph
                        width: parent.width
                        height: 40

                        property var ch: Services.Vitals.cpuHist
                        property var mh: Services.Vitals.memHist
                        onChChanged: requestPaint()
                        onMhChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        Component.onCompleted: requestPaint()

                        function line(arr, color) {
                            const n = arr.length
                            if (n < 1) return
                            const ctx = getContext("2d")
                            const h = height, w = width
                            const y = v => Math.round((1 - Math.max(0, Math.min(100, v)) / 100) * (h - 2)) + 1
                            ctx.beginPath()
                            if (n === 1) {
                                ctx.moveTo(0, y(arr[0]))
                                ctx.lineTo(w, y(arr[0]))
                            } else {
                                for (let i = 0; i < n; i++) {
                                    const x = i / (n - 1) * (w - 1) + 0.5
                                    if (i === 0) ctx.moveTo(x, y(arr[i]))
                                    else ctx.lineTo(x, y(arr[i]))
                                }
                            }
                            ctx.strokeStyle = color
                            ctx.lineWidth = 1.5
                            ctx.lineJoin = "round"
                            ctx.lineCap = "round"
                            ctx.stroke()
                        }

                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.clearRect(0, 0, width, height)
                            line(mh, Services.Colors.textMuted)
                            line(ch, Services.Colors.accent)
                        }
                    }

                    Row {
                        width: parent.width
                        height: 12
                        spacing: 10

                        Text {
                            font.family: Services.Fonts.family
                            text: "\u2191 " + Services.Vitals.netUpLabel
                            font.pixelSize: 10
                            font.bold: true
                            color: Services.Colors.accent
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            font.family: Services.Fonts.family
                            text: "\u2193 " + Services.Vitals.netDownLabel
                            font.pixelSize: 10
                            color: Services.Colors.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                }
            }

            Row {
                width: parent.width
                height: 24
                spacing: 8

                Text {
                    font.family: Services.Fonts.family
                    id: notifTitle

                    // total notifications, not group rows — "3" means three
                    // messages even when they're folded into one app header
                    text: "Notifications" + (Services.Notifications.history.length > 0 ? "  " + Services.Notifications.history.length : "")
                    color: Services.Colors.text
                    font.pixelSize: 14
                    font.bold: true
                    height: 24
                    verticalAlignment: Text.AlignVCenter
                }

                Item {
                    width: Math.max(4, parent.width - notifTitle.width - clearAll.width - parent.spacing * 2)
                    height: 1
                }

                // tonal pill instead of a bare accent word — matches the
                // settings window's action buttons
                Rectangle {
                    id: clearAll

                    height: 24
                    radius: 12
                    width: clearAllLabel.width + 20
                    color: Services.Colors.surface

                    Text {
                        font.family: Services.Fonts.family
                        id: clearAllLabel

                        anchors.centerIn: parent
                        text: "Clear all"
                        font.pixelSize: 11
                        font.bold: true
                        color: Services.Colors.accent
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Notifications.history = []
                    }

                }

            }

            // one row per app, mirrored from Services.Notifications.history
            // (see root.syncHistory) — the transitions below need real row
            // inserts/removes, not array resets
            ListModel {
                id: grpModel

                Component.onCompleted: root.syncHistory()
            }

            Connections {
                target: Services.Notifications

                function onHistoryChanged() { root.syncHistory() }
            }

            ListView {
                id: historyList

                width: parent.width
                height: parent.height - 144   // vitals card + title row
                clip: true
                spacing: 8
                model: grpModel

                // M3 spec motion (m3.material.io/styles/motion): new cards
                // ENTER by dropping one row up into the top slot (the 64px
                // drop) — the slide rides the bounce spring
                // (overshoots its slot and settles, M3E spatial = springs)
                // while the fade keeps emphasized decelerate; removals
                // accelerate out with no bounce; rows pushed aside spring
                // into their new slots, so "Clear all" collapses as one
                // soft bouncing cascade.
                add: Transition {
                    ParallelAnimation {
                        NumberAnimation {
                            property: "opacity"
                            from: 0
                            to: 1
                            duration: Services.Motion.emphasizedEnter
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                        SpringAnimation {
                            property: "y"
                            from: -64
                            spring: Services.Motion.bounceSpring
                            damping: Services.Motion.bounceDamping
                        }
                    }
                }

                remove: Transition {
                    NumberAnimation {
                        property: "opacity"
                        to: 0
                        duration: Services.Motion.emphasizedExit
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedAccelerate
                    }
                }

                displaced: Transition {
                    // shoved rows overshoot their new slot slightly and
                    // spring back — M3E spatial settles with a bounce
                    SpringAnimation {
                        property: "y"
                        spring: Services.Motion.bounceSpring
                        damping: Services.Motion.bounceDamping
                    }
                }

                // shown when there's nothing to display — same idea as a
                // Waybar module returning an empty string and disappearing
                Text {
                    font.family: Services.Fonts.family
                    anchors.centerIn: parent
                    visible: historyList.count === 0
                    text: "No notifications"
                    color: Services.Colors.textMuted
                    font.pixelSize: 12
                }

                // one group per app: header (icon, name, count, caret) with
                // the app's messages folded underneath. Click the header to
                // expand/collapse, right-click it to dismiss the whole
                // group; left-click a message runs its default action (same
                // path as the bar pill), right-click dismisses just it.
                delegate: Rectangle {
                    id: groupCard

                    width: historyList.width
                    radius: 10
                    color: Services.Colors.surface

                    // this app's messages, newest-first — a binding on the
                    // service's history, so a dismiss refreshes the group's
                    // contents without a row-model update
                    readonly property var notifs: Services.Notifications.notifsFor(model.name)
                    readonly property string appIcon: notifs.length > 0 ? notifs[0].appIcon : ""
                    readonly property bool open: model.expanded

                    // drives the badge on the app icon — a folded group
                    // still tells you something urgent is inside
                    readonly property bool hasCritical: {
                        for (let i = 0; i < notifs.length; i++)
                            if (notifs[i].urgency === NotificationUrgency.Critical) return true
                        return false
                    }

                    // header (always) + folded rows when open; the spring
                    // makes expand/collapse settle like the pill morph
                    height: headerRow.height + notifsCol.height + (notifsCol.height > 0 ? 6 : 0)
                    Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                    Row {
                        id: headerRow
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        height: 40
                        spacing: 8

                        Item {
                            width: 18
                            height: 18
                            anchors.verticalCenter: parent.verticalCenter

                            IconImage {
                                anchors.fill: parent
                                source: groupCard.appIcon !== "" ? Quickshell.iconPath(groupCard.appIcon, true) : ""
                                visible: source !== ""
                            }

                            // fallback bell for senders with no icon — the
                            // glyph the old per-notification rows used
                            Text {
                                anchors.centerIn: parent
                                text: "󰂚"
                                font.family: Services.Fonts.family
                                font.pixelSize: 12
                                color: Services.Colors.accent
                                visible: groupCard.appIcon === ""
                            }

                            // urgent dot on the icon corner — surfaces
                            // critical content even when the group is
                            // folded shut
                            Rectangle {
                                visible: groupCard.hasCritical
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                width: 7
                                height: 7
                                radius: 4
                                color: Services.Colors.critical
                                border.width: 1.5
                                border.color: Services.Colors.surface
                            }
                        }

                        Text {
                            id: appNameText
                            font.family: Services.Fonts.family
                            text: model.name
                            font.pixelSize: 12
                            font.bold: true
                            color: Services.Colors.text
                            anchors.verticalCenter: parent.verticalCenter
                            // absorbs the slack so pill + caret pin right
                            width: Math.max(40, parent.width - 18 - countPill.width - caret.width - parent.spacing * 3)
                            elide: Text.ElideRight
                        }

                        Rectangle {
                            id: countPill
                            height: 16
                            radius: 8
                            width: countLabel.width + 12
                            anchors.verticalCenter: parent.verticalCenter
                            color: Services.Colors.background

                            Text {
                                id: countLabel
                                anchors.centerIn: parent
                                text: groupCard.notifs.length
                                font.family: Services.Fonts.family
                                font.pixelSize: 10
                                font.bold: true
                                color: Services.Colors.accent
                            }
                        }

                        Text {
                            id: caret
                            font.family: Services.Fonts.family
                            text: ""
                            font.pixelSize: 11
                            color: Services.Colors.textMuted
                            anchors.verticalCenter: parent.verticalCenter
                            rotation: groupCard.open ? 0 : -90   // ▼ open, ▶ closed
                        }
                    }

                    // click = expand/collapse, right-click = dismiss the
                    // whole group — sits over the header band only, so the
                    // message rows keep their own handlers
                    MouseArea {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        height: headerRow.height
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (mouse.button === Qt.RightButton)
                                Services.Notifications.dismissApp(model.name)
                            else
                                grpModel.setProperty(index, "expanded", !groupCard.open)
                        }
                    }

                    Column {
                        id: notifsCol
                        anchors.top: headerRow.bottom
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 0

                        Rectangle {
                            width: parent.width
                            height: 1
                            color: Services.Colors.background
                            visible: groupCard.open && groupCard.notifs.length > 0
                        }

                        // empty model when folded — the column collapses to
                        // 0 height and the card's height spring animates it
                        Repeater {
                            model: groupCard.open ? groupCard.notifs : []

                            delegate: Rectangle {
                                width: notifsCol.width
                                height: nTexts.height + 10
                                color: "transparent"

                                // declared first so it stacks UNDER the
                                // action chips: a chip takes its own click,
                                // plain text still falls through to
                                // invoke/dismiss as before
                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: (mouse) => {
                                        if (mouse.button === Qt.RightButton)
                                            Services.Notifications.dismissNotification(modelData)
                                        else
                                            Services.Notifications.invokeDefault(modelData)
                                    }
                                }

                                // critical entries carry a red rail in the
                                // icon gutter — scannable in a stack of
                                // near-identical rows
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 8
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: Math.max(0, nTexts.height - 4)
                                    radius: 1.5
                                    visible: modelData.urgency === NotificationUrgency.Critical
                                    color: Services.Colors.critical
                                }

                                Column {
                                    id: nTexts
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    // aligns under the app name (icon gutter)
                                    anchors.leftMargin: 36
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 1

                                    Text {
                                        font.family: Services.Fonts.family
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: modelData.summary
                                        visible: modelData.summary !== ""
                                        // urgency tints the headline: critical
                                        // pushes, low stays out of the way
                                        color: modelData.urgency === NotificationUrgency.Critical ? Services.Colors.critical
                                             : modelData.urgency === NotificationUrgency.Low ? Services.Colors.textMuted
                                             : Services.Colors.text
                                        font.pixelSize: 11
                                        font.bold: true
                                    }

                                    Text {
                                        font.family: Services.Fonts.family
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: modelData.body
                                        visible: modelData.body !== ""
                                        color: Services.Colors.textMuted
                                        font.pixelSize: 10
                                    }

                                    // the sender's own actions as tonal
                                    // pills — 0 height when it offered none
                                    Item {
                                        width: parent.width
                                        height: chipRow.implicitHeight > 0 ? chipRow.implicitHeight + 5 : 0

                                        Row {
                                            id: chipRow
                                            y: 5
                                            spacing: 6

                                            Repeater {
                                                model: Services.Notifications.chipsFor(modelData)

                                                delegate: Rectangle {
                                                    width: chipLabel.width + 16
                                                    height: 20
                                                    radius: 10
                                                    color: chipArea.pressed ? Services.Colors.accent : Services.Colors.background

                                                    Text {
                                                        id: chipLabel
                                                        anchors.centerIn: parent
                                                        text: modelData.text
                                                        font.family: Services.Fonts.family
                                                        font.pixelSize: 10
                                                        font.bold: true
                                                        color: chipArea.pressed ? Services.Colors.background : Services.Colors.accent
                                                    }

                                                    MouseArea {
                                                        id: chipArea
                                                        anchors.fill: parent
                                                        cursorShape: Qt.PointingHandCursor
                                                        onClicked: modelData.invoke()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

            }

        }

    }

    // ---------------- Reusable square toggle tile ----------------
    // Bento-grid tile, icon-forward. When active it becomes a solid
    // accent chip with a dark glyph — the same "filled = on" language as
    // the settings window's selected chips. Two feedback layers:
    //   1. `flash` — instant tap feedback, always, no matter what: "did
    //      my click register", independent of nmcli/bluetoothctl timing.
    //   2. `color` bound to `active` — follows the real service state:
    //      "did the toggle actually flip".
    component SquareToggle: Rectangle {
        id: tile

        property string icon: ""
        property string label: ""
        property bool active: false

        signal toggled()
        signal rightClicked()

        width: 106
        height: 64
        radius: 14
        color: tile.active ? Services.Colors.accent : Services.Colors.surface
        // Press-down scale — starts the instant the cursor is down, not
        // on release. This alone tells you the tap landed. On release the
        // pop spring overshoots so the tile bounces back (M3E expressive
        // toggle), and the active state lifts the scale a touch so the
        // flip is felt, not just seen.
        property real pressEff: 1
        scale: (active ? 1.04 : 1) * pressEff

        // Flash overlay — a brightness pulse on every click, independent
        // of `active` (fires even if the underlying toggle fails).
        Rectangle {
            id: flash

            anchors.fill: parent
            radius: parent.radius
            color: Services.Colors.text
            opacity: 0
        }

        SequentialAnimation {
            id: flashAnim

            NumberAnimation {
                target: flash
                property: "opacity"
                to: 0.22
                duration: Services.Motion.short1
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.standardCurve
            }

            NumberAnimation {
                target: flash
                property: "opacity"
                to: 0
                duration: Services.Motion.short4
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.standardDecelerate
            }

        }

        Column {
            anchors.centerIn: parent
            spacing: 8

            Text {
                font.family: Services.Fonts.family
                text: tile.icon
                font.pixelSize: 22
                color: tile.active ? Services.Colors.background : Services.Colors.text
                anchors.horizontalCenter: parent.horizontalCenter

                Behavior on color {
                    ColorAnimation {
                        duration: Services.Motion.short2
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.standardCurve
                    }

                }

            }

            Text {
                font.family: Services.Fonts.family
                text: tile.label
                font.pixelSize: 12
                font.bold: tile.active
                color: tile.active ? Services.Colors.background : Services.Colors.text
                anchors.horizontalCenter: parent.horizontalCenter
                elide: Text.ElideRight
                width: tile.width - 12
                horizontalAlignment: Text.AlignHCenter

                Behavior on color {
                    ColorAnimation {
                        duration: Services.Motion.short2
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.standardCurve
                    }

                }

            }

        }

        MouseArea {
            id: pressArea

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            onPressedChanged: tile.pressEff = pressed ? 0.94 : 1
            onClicked: (mouse) => {
                flashAnim.restart();
                if (mouse.button === Qt.RightButton)
                    tile.rightClicked();
                else
                    tile.toggled();
            }
        }

        Behavior on color {
            ColorAnimation {
                duration: Services.Motion.short2
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.standardCurve
            }

        }

        Behavior on scale {
            SpringAnimation {
                spring: Services.Motion.popSpring
                damping: Services.Motion.popDamping
            }
        }

    }

}
