import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
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
        WlrLayershell.layer: (pill.osdVisible || pill.notifVisible || Services.Launcher.open || Services.Themes.open || Services.Wallpapers.open || Services.ControlCenter.open || Services.ClockCard.open || Services.Clipboard.open || Services.PowerMenu.open || Services.SettingsApp.open) ? WlrLayer.Overlay : WlrLayer.Top
        anchors{ top: true; left:true; right:true}

        // FIXED window height = the tallest size any pill mode can reach
        // (the old `Math.min(560, pill.height + 24)` bound made the surface
        // resize on EVERY spring frame — hyprctl measured 54 -> 346 -> 54
        // frame by frame during a launcher open — and a per-frame surface
        // resize is precisely what made morphs choppy: Qt/compositor scales
        // the in-flight frame to the new size, which is where the visible
        // "text and icons stretch" came from). The pill now springs inside
        // a static surface: nothing resizes, nothing gets scaled.
        //
        // `mask` keeps input correct despite the big surface: only the
        // pill + the activity chips are clickable, everything else passes
        // through to the windows behind. The chips (media/weather/updates/
        // rec) live just past the pill's right edge — they need their own
        // combined region or their MouseAreas are click-through (which is
        // why the media chip never opened its popup). Child regions with
        // `item` resolve that item's geometry directly, so the rects land
        // where the chips actually are.
        implicitHeight: 560
        // True while one of the pill's modal panels owns the screen. The
        // pill's modes are exclusive (each panel's openPanel() closes the
        // others), so at most one is ever set — this just means "a panel is
        // up". SettingsApp is deliberately absent: it is its own window with
        // its own mask, not a pill mode.
        readonly property bool panelOpen: toplevel.ownsOverlay(Services.Launcher) || toplevel.ownsOverlay(Services.Themes)
            || toplevel.ownsOverlay(Services.Wallpapers) || toplevel.ownsOverlay(Services.ControlCenter)
            || toplevel.ownsOverlay(Services.ClockCard) || toplevel.ownsOverlay(Services.Clipboard)
            || toplevel.ownsOverlay(Services.PowerMenu)

        // Multi-monitor overlay ownership: services hold ONE shared `open`
        // flag, but each screen has its own bar instance. Services record the
        // screen that opened them (ownerScreen, captured at open time from
        // Hyprland's focused monitor = where the cursor is), and only that
        // bar reacts. Before this, every bar morphed AND armed its own
        // HyprlandFocusGrab; the duplicate grabs fought over the keyboard,
        // cleared each other instantly, and no panel ever appeared.
        function ownsOverlay(svc) {
            return svc.open && toplevel.screen && svc.ownerScreen === toplevel.screen.name
        }

        // Click-away dismissal. The mask confines input to the pill + the
        // activity chips, so a panel sitting over the desktop never receives
        // a click outside itself and could not be dismissed by clicking away.
        // outsideCatcher is that missing half — declared BEFORE the pill so
        // the pill's own MouseAreas stay above it and a click inside the
        // panel still lands on the panel, never on the catcher. `enabled`
        // (not `visible`) is what gates it: enabled:false reliably removes an
        // item from hit-testing, whereas the input mask is driven by the
        // Region below, not by this item's visibility.
        MouseArea {
            id: outsideCatcher
            anchors.fill: parent
            enabled: toplevel.panelOpen
            onClicked: toplevel.dismissPanels()
        }

        function dismissPanels() {
            if (Services.Clipboard.open)    { Services.Clipboard.close(); return }
            if (Services.Launcher.open)     { Services.Launcher.closeLauncher(); return }
            if (Services.Themes.open)       { Services.Themes.closePicker(); return }
            if (Services.Wallpapers.open)   { Services.Wallpapers.closePicker(); return }
            if (Services.ControlCenter.open){ Services.ControlCenter.close(); return }
            if (Services.ClockCard.open)    { Services.ClockCard.close(); return }
            if (Services.PowerMenu.open)    { Services.PowerMenu.open = false; return }
        }

        mask: Region {
            item: pill
            Region { item: activityRow }
            // Full-surface catch for click-away dismissal.
            //
            // Region has NO `when` property — its documented properties are
            // only item, shape, x, y, width, height, the four *Radius ones,
            // regions and intersection — so a `when:` binding here would be a
            // runtime "non-existent property" warning and would also fail the
            // zero-warning gate. The gate is therefore done by SIZING: a
            // zero-size region contributes no input, which is what keeps the
            // resting bar passing every click through to the windows below.
            // (Same trick omarchy's shell/Ui/KeyboardPanel.qml uses for its
            // full-screen dismissal region.)
            Region {
                x: 0
                y: 0
                width: toplevel.panelOpen ? toplevel.width : 0
                height: toplevel.panelOpen ? toplevel.height : 0
            }
        }

        // Decouple "how tall the window visually is" from "how much space
        // Hyprland reserves for it" — exact fix for the launcher clipping.
        // Auto (the default) ties exclusion zone to the window's real size,
        // which is why bumping implicitHeight earlier pushed the whole
        // workspace down. Normal + a fixed exclusiveZone keeps the reserved
        // strip pinned at the rest-state bar height no matter how tall the
        // pill grows for notif/launcher/etc.
        exclusionMode: ExclusionMode.Normal
        exclusiveZone: 35

        color:"transparent"
        // Clipboard.open was missing here, so the paste window sat at
        // WlrKeyboardFocus.None: its search field could never take focus and
        // Escape could not be delivered at all. Everything with a text field
        // needs this — an unfocusable field means no keyboard input and no
        // Escape, because a layershell surface with no focus never sees keys.
        WlrLayershell.keyboardFocus: (Services.Launcher.open || Services.Themes.open || Services.Wallpapers.open || Services.Clipboard.open) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Rectangle{
            id: pill
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.top: parent.top
            // always clip: the tray chip lives INSIDE the pill now (its
            // room is carved out of both rest widths via pill.traySlot),
            // so nothing is meant to hang past the edge — clipping also
            // keeps any spring overshoot from peeking out.
            clip: true

            // same idea as Pill.qml's restCorner/openCorner: full pill-shaped
            // corners for short/fixed-height modes, a normal rounded-rect
            // corner for anything that can genuinely grow tall — height/2 on
            // a 200-300px pill (launcher, theme, a long notification) looks
            // like a stretched oval, not a pill. Listed by mode, not by an
            // arbitrary height threshold, so it's obvious which is which.
            // "power" joined this list once its swatches grew from 36px
            // circles to 64px squares — tall enough now to have the same
            // problem. "controlcenter" joins for the same reason — 380px tall.
            readonly property bool tallMode: mode === "launcher" || mode === "theme" || mode === "notif" || mode === "power" || mode === "controlcenter" || mode === "wallpaper" || mode === "clock" || mode === "clipboard"
            readonly property real morphRadius: tallMode ? 18 : height / 2
            bottomLeftRadius: morphRadius
	    bottomRightRadius: morphRadius
            // color:"#282828"
            color: Services.Colors.background

            property bool osdVisible: false
            property string osdType: "volume"
            property real osdValue: 0

            // compact rest capsule: expands on hover (or click) into the
            // full segmented row. Collapse waits for the grace timer, so a
            // fast cursor crossing never flickers it — popup modes are
            // unaffected (each has its own target size).
            property bool restExpanded: false

            // Escape closes the paste window even when focus is not sitting
            // in its search field (e.g. after clicking around the list).
            // Keys handlers fire on the focused item and then bubble up the
            // parent chain, so this catches whatever the children did not
            // already accept. The search field handles Escape first — first
            // press clears the query, second closes — and marks it accepted,
            // so the two never fight.
            Keys.onPressed: (event) => {
                if (event.key === Qt.Key_Escape && Services.Clipboard.open) {
                    Services.Clipboard.close()
                    event.accepted = true
                }
            }

            // Tray popup visibility. This used to be "trayHover" and it used
            // to be set by hoverArea — i.e. mousing ANYWHERE across the pill
            // expanded the tray inline. It is now "is the drop-down tray popup
            // showing", armed only by the arrow itself (trayChip) and by the
            // popup's own hover, which is what a down-chevron next to the
            // status module actually promises.
            property bool trayOpen: false

            // Hover never closes on its own — it only opens and (re)arms
            // trayIdle. Dismissal is the timer's job, and that is what buys
            // the pointer time to travel DOWN from the arrow into the popup:
            // leaving the arrow immediately enters the popup, and if
            // hover-out closed, the popup would vanish mid-gesture.
            function trayTouch() {
                // No hasIcons guard any more: the arrow stays put and always
                // answers the hover, so an empty tray says "No tray apps"
                // rather than the chevron simply dead-ending. trayIdle still
                // retires it on its own like any other hover.
                trayOpen = true
                trayIdle.restart()
            }

            MouseArea {
                id: hoverArea
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton

                onContainsMouseChanged: {
                    // hover does NOT morph the pill into the full segmented
                    // row any more, and it no longer touches the tray — the
                    // arrow owns that now. restExpanded stays click-only.
                    if (!containsMouse) collapseTimer.start()
                    else collapseTimer.stop()
                }
                onClicked: {
                    // clicking empty capsule area pins the full segmented row
                    // while the pointer is here; content children keep their
                    // own clicks
                    pill.restExpanded = true
                    collapseTimer.restart()
                }
            }

            Timer {
                id: collapseTimer
                interval: 350
                // guard: a click restarts this while the pointer is still on
                // the bar — don't collapse the pinned row under a live hover
                onTriggered: if (!hoverArea.containsMouse) pill.restExpanded = false
            }

            Timer {
                id: trayIdle
                // The popup's entire dismissal policy: "disappears after a few
                // seconds if hover isn't detected". Hovering the arrow or the
                // popup restarts it, so it can only fire once the pointer has
                // genuinely stopped hovering — and 2.6s is also the travel
                // budget from the arrow down to the popup.
                interval: 2600
                onTriggered: pill.trayOpen = false
            }

            property bool notifVisible: false
            property var currentNotification: null

            // How tall the results list should be: capped at 6 visible rows
            // (44px each) so a huge app list doesn't grow the pill past the
            // screen — it scrolls past that instead. Both the pill's target
            // height (below) and the actual ListView height read this same
            // function, so they can't drift apart like width/height used to.
            function launcherListHeight() {
                const n = Math.min(Services.Launcher.results.length, 6)
                return n > 0 ? n * 44 : 40   // 40 = height of the "No results" line
            }

            // The delete dialog renders OVER the list, so on a short search
            // (one result → 44px list) its box overflowed the pill's target
            // height and got cropped by the pill background. While the dialog
            // is up the pill reserves at least the box + 8px breathing top
            // and bottom; the list itself keeps its natural height, so tall
            // lists look exactly as before and only short ones grow.
            function confirmOverlayHeight() {
                const natural = launcherListHeight()
                if (!Services.Launcher.confirmDelete) return natural
                return Math.max(natural, deleteBody.implicitHeight + 42)
            }

            // Theme strip is a single horizontal row (5 visible, scrolls
            // sideways past that). Height comes from Services.Themes.geom —
            // grows with the1/2/3 picker size.
            function themeGridHeight() {
                return Services.Themes.geom.listH
            }

            // Power swatches are 64px square with 14px gaps + 12px side
            // margins. Computed from the actual action count instead of a
            // hardcoded width, same reasoning as launcherListHeight — if you
            // add a 5th or 6th power action later, this doesn't need touching.
            function powerRowWidth() {
                const n = Services.PowerMenu.actions.length
                const swatch = 64, spacing = 14, margin = 24
                return n * swatch + Math.max(0, n - 1) * spacing + margin
            }

            // Wallpaper strip = the same M3 hero carousel as the theme
            // picker (PillWallpaperContent) — height comes from
            // Services.Themes.geom so one setSize switch (1/2/3) keeps
            // both pills identical: hero + two vertical-rect peeks + label.
            function wallpaperStripHeight() {
                return Services.Themes.geom.listH
            }

            // restStyle "compact" AND not hover-expanded = the tiny capsule
            function compactAtRest() {
                return Services.Settings.barRestStyle === "compact" && !restExpanded
            }

            // Room reserved for the system-tray chip at the pill's right
            // edge (chip width + 8px breathing space). Feeds BOTH rest
            // widths so the chip is always fully inside the bar — nothing
            // straddles the edge any more.
            readonly property real traySlot: trayChip.visible ? trayChip.width + 14 : 0

            // content-hug widths: the capsule/row IS the measure, so the
            // pill grows when content does (starting a media player widens
            // the bar!) instead of floating in a fixed 620 box. All values
            // are implicit sizes, independent of pill width — no feedback
            // loop with modes.rest.
            function compactBarWidth() {
                return compactRow.implicitWidth + 32 + traySlot
            }
            function fullBarWidth() {
                // Guaranteed breathing room around the dead-centre dots:
                // each side declares its own need (edge margin + its own
                // cluster + GAP + half the dots) and the pill takes TWICE
                // the larger need — so both gaps clear GAP no matter how
                // wide the left chip, status group or tray grow. The old
                // fixed slack gave the two gaps a combined 32px to share,
                // and a wider SSID or one more tray icon pushed them into
                // each other ("cramped, things overlapping" at full row).
                const gap = 20
                const half = workspacesItem.implicitWidth / 2
                const leftNeed = 12 + leftRow.implicitWidth + 24 + gap + half
                const rightNeed = 12 + traySlot + rightGroup.implicitWidth
                    + gap + half
                return 2 * Math.max(leftNeed, rightNeed)
            }

            // one word describes what the pill is currently showing —
            // same idea as Pill.qml's `mode`. Order matters: first match wins.
            readonly property string mode: toplevel.ownsOverlay(Services.Launcher) ? "launcher"
                : toplevel.ownsOverlay(Services.Themes) ? "theme"
                : toplevel.ownsOverlay(Services.Wallpapers) ? "wallpaper"
                : toplevel.ownsOverlay(Services.ControlCenter) ? "controlcenter"
                : toplevel.ownsOverlay(Services.ClockCard) ? "clock"
                : toplevel.ownsOverlay(Services.Clipboard) ? "clipboard"
                : pill.osdVisible ? "osd"
                : pill.notifVisible ? "notif"
                : toplevel.ownsOverlay(Services.PowerMenu) ? "power"
                : "rest"

            // lookup table: mode -> target size. Adding a new pill state
            // (like Pill.qml's `surfaces`) is one entry here, not a new
            // branch in a width ternary and a separate one in a height ternary.
            // Thunks (functions), not plain values, because "notif", "launcher"
            // and "theme" need to read live content sizes each time they're asked.
            readonly property var modes: ({
                rest:         () => pill.compactAtRest()
                    ? Qt.size(pill.compactBarWidth(), 30)
                    : Qt.size(pill.fullBarWidth(), 35),
                launcher:     () => Qt.size(360, 12 + 30 + 8 + pill.confirmOverlayHeight() + 12),
                theme:        () => Qt.size(Services.Themes.geom.pillW, 24 + pill.themeGridHeight()),
                wallpaper:    () => Qt.size(Services.Themes.geom.pillW, 24 + pill.wallpaperStripHeight()),
                controlcenter:() => Qt.size(760, 380),
                clock:        () => Qt.size(620, 520),
                osd:          () => Qt.size(220, 35),
                notif:        () => Qt.size(420, Math.max(35, notificationContent.implicitHeight + 22)),
                power:        () => Qt.size(pill.powerRowWidth(), 24 + 64),
                clipboard:    () => Qt.size(430, 12 + 30 + 8 + clipboardContent.listH + 12)
            })

            readonly property size targetSize: (modes[mode] || modes.rest)()

            width: targetSize.width
            height: targetSize.height

            // M3 Expressive: the pill morph runs on the spatial spring —
            // velocity carries across retargets, so flipping modes mid-morph
            // keeps momentum instead of restarting from zero
            Behavior on width {
                SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping }
            }

            Behavior on height {
                SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping }
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
                        // only the owning bar's searchField may take focus —
                        // a second display means a second searchField
                        if (toplevel.ownsOverlay(Services.Launcher))
                            searchField.forceActiveFocus()
                    } else {
                        searchField.text = ""
                    }
                }
            }

            Item {
                id: normalContent
                anchors.fill: parent
                opacity: pill.mode === "rest" ? 1 : 0
                // opacity alone does NOT gate input in Qt Quick -- an
                // invisible item still takes clicks. The `|| opacity > 0.01`
                // tail keeps the fade-out animating; the condition half is
                // what makes it live on frame 1 (search fields need focus).
                visible: (pill.mode === "rest") || opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                // ----- compact capsule (restStyle "compact", collapsed) -----
                // time · workspace dots · battery % — the pill hugs this row
                // (30px tall) and springs open to the full segmented row on
                // hover/click (grace timer lives with the pill props).
                Row {
                    id: compactRow
                    anchors.centerIn: parent
                    // the tray slot eats the pill's right side — pull the
                    // capsule row left by half of it so its left/right
                    // breathing room stays symmetric (16/16 around row+slot)
                    anchors.horizontalCenterOffset: -pill.traySlot / 2
                    spacing: 14
                    // crossfade instead of pop: the capsule row and the
                    // segmented row swap places while the pill springs,
                    // so both sides fade through each other
                    opacity: pill.compactAtRest() ? 1 : 0
                    visible: opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Services.Motion.effects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }

                    Clock {}

                    Workspaces {
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    BatteryRing {
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }

                // ----- full segmented row: left chip | dots | right chips -----
                // restStyle "wide" shows this always; "compact" shows it while
                // hover-expanded. The surface chip around clock · date is half
                // the segmented-pill identity — media/recording/updates moved
                // OUT to the activity chips that slide from the pill's right
                // edge (they need to be reachable from the compact capsule too).
                Rectangle {
                    id: leftChip
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 26
                    width: leftRow.width + 24
                    radius: height / 2
                    color: Services.Colors.surface
                    opacity: !pill.compactAtRest() ? 1 : 0
                    visible: opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Services.Motion.effects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }

                    Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
                    Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                    Row {
                        id: leftRow
                        anchors.centerIn: parent
                        spacing: 10

                        Clock {
                            id: clockItem
                        }

                        // date joins the clock once the row is wide enough for it
                        Text {
                            font.family: Services.Fonts.family
                            anchors.verticalCenter: parent.verticalCenter
                            text: Services.Time.date
                            color: Services.Colors.textMuted
                            font.pixelSize: 12
                        }
                    }
                }

                // workspaces sit dead center of the bar, independent of how wide
                // the left/right groups are — like Waybar's modules-center array
                Workspaces {
                    id: workspacesItem
                    anchors.centerIn: parent
                    opacity: !pill.compactAtRest() ? 1 : 0
                    visible: opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Services.Motion.effects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }
                }

                Row{
                    id: rightGroup
                    anchors.right:parent.right
                    // + traySlot: the tray chip sits to the right of this
                    // row (inside the pill), so the row shifts left to
                    // leave the slot open
                    anchors.rightMargin:12 + pill.traySlot
                    anchors.verticalCenter:parent.verticalCenter
                    spacing: 10
                    // crossfade with the compact capsule — see compactRow
                    opacity: !pill.compactAtRest() ? 1 : 0
                    visible: opacity > 0.01

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Services.Motion.effects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }

                    // recording + updates indicators moved out to the
                    // activity chips that slide from the pill's right edge —
                    // they must be reachable from the compact capsule too,
                    // not just from this expanded row.


                    
                    // clipboard history — same self-contained glyph+MouseArea
                    // shape as the ⏻ below; opens the pill's clipboard mode
                    // (\uD838\uDCEA = U+F0EA, FA clipboard, covered by Mononoki)
                    Text {
                        font.family: Services.Fonts.family
                        text: "\uD838\uDCEA"
                        color: Services.Colors.text
                        font.pixelSize: 14
                        font.bold: true
                        anchors.verticalCenter: parent.verticalCenter

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Clipboard.toggle()
                        }
                    }

                    // battery/network/power grouped into one pill — clicking anywhere
                    // in it opens the control center. the power icon keeps its own
                    // MouseArea on top, so clicking IT still opens the power menu
                    // directly (it used to be commented out = dead control, not anymore)
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

                            // battery ring with the wifi glyph in its middle —
                            // clicking it (or the chip around it) opens the CC
                            BatteryRing {
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // network value: SSID for wifi, plain state otherwise —
                            // elided so one long SSID can't blow the pill open
                            Text {
                                font.family: Services.Fonts.family
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, 84)
                                elide: Text.ElideRight
                                text: Services.Network.isWifi ? Services.Network.name
                                    : (Services.Network.connected ? "Wired" : "Offline")
                                color: Services.Colors.textMuted
                                font.pixelSize: 11
                            }

                            Text {
                                font.family: Services.Fonts.family
                                text: "⏻"
                                color: Services.Colors.text
                                font.pixelSize: 14
                                font.bold: true
                                anchors.verticalCenter: parent.verticalCenter

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: Services.PowerMenu.open = !Services.PowerMenu.open
                                }
                            }
                        }
                    }
                }

                // ---------------- system tray: the arrow ----------------
                // The chip no longer holds the icons — it is just the trigger.
                // pill.traySlot still carves its room out of both rest widths
                // (it reads trayChip.width), so the pill's width math is
                // unchanged in shape; the slot is just narrower now that the
                // chip is arrow-sized instead of arrow-plus-icon-row.
                //
                // Position is unchanged: still anchored to the pill's right
                // edge with rightGroup shifted left by traySlot, which puts
                // this immediately after statusGroup (battery + network +
                // power) — the last child of rightGroup.
                Rectangle {
                    id: trayChip
                    readonly property bool expanded: pill.trayOpen
                        // no more `|| !pill.compactAtRest()`: the wide rest
                        // row used to keep the icons permanently inline. The
                        // tray is hover-driven now, and leaving it inline in
                        // one state but popups in the other meant the arrow
                        // pointed at nothing whenever the row was open.
                        // (hasIcons is gone too — visibility no longer
                        // depends on tray contents, see below.)

                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    height: 26
                    width: 26
                    radius: 13
                    color: trayArea.containsMouse || trayChip.expanded
                        ? Services.Colors.surfaceAlt : Services.Colors.surface
                    // ALWAYS visible. It used to be gated on
                    // SystemTray.items.values.length > 0, and this machine has
                    // no tray applet installed at all (nm-applet, blueman-applet,
                    // etc. are all absent), so the condition was permanently
                    // false — the arrow has literally never rendered, in the old
                    // inline chip and in this one. Hiding an affordance only
                    // because it currently has nothing to reveal also makes the
                    // bar's chrome change shape as tray apps come and go, which
                    // drags the whole pill layout with it. Now it's constant and
                    // the EMPTY state says so instead (trayEmptyHint, below).

                    // ColorAnimation, NOT NumberAnimation. NumberAnimation
                    // drives a property by reading/writing it as a double, and
                    // QColor has no numeric conversion — QVariant::toDouble()
                    // on a colour yields 0.0, so the animation ran 0 -> 0 and
                    // wrote back 0x000000. That turned this chip pure black
                    // instead of surface, and the same bug on trayArrow (below)
                    // turned the chevron black too, so both were black-on-black
                    // and the arrow looked like a solid black dot. The rest of
                    // the config's 51 colour Behaviors all use ColorAnimation;
                    // these three were the only ones that didn't.
                    Behavior on color {
                        ColorAnimation {
                            duration: Services.Motion.effectsFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.standardCurve
                        }
                    }

                    // Down-chevron, not the old sideways "›". A down-chevron
                    // promises content below, which is now true — the popup
                    // drops down out of the bar (the bar is the TOP layer, so
                    // Meet's upward pop is mirrored). Rotating 180° turns it
                    // into the up-chevron that says "already open".
                    Text {
                        font.family: Services.Fonts.family
                        id: trayArrow
                        // NOT centerIn. U+2304 hangs ~4px below the centre of
                        // its em box (measured on a capture: chip centre y14.5,
                        // chevron ink centre y18.5), so centring the Text ITEM
                        // left the visible chevron sitting low in the circle.
                        // Lifting it 4px fixes the resting state — but rotation
                        // spins the item about ITS OWN centre, which mirrors
                        // that off-centre ink 4px the OTHER way. So the offset
                        // reverses while open: closed lands on 14.5, open lands
                        // on 14.5 too. A fixed offset would have centred the
                        // rest state and thrown the open one to ~6.5, near the
                        // chip's top edge.
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: trayChip.expanded ? 4 : -4
                        text: "⌄"
                        font.pixelSize: 15
                        color: trayChip.expanded ? Services.Colors.accent : Services.Colors.text
                        rotation: trayChip.expanded ? 180 : 0
                        Behavior on rotation { SpringAnimation { spring: Services.Motion.spatialFastSpring; damping: Services.Motion.spatialFastDamping } }
                        // ColorAnimation (see the note on the chip above):
                        // with NumberAnimation this made the chevron #000000,
                        // so it was invisible against the blackened chip.
                        // Colour now stays Services.Colors.text — the exact
                        // value modules/Clock.qml uses for the clock — and
                        // flips to accent only while the tray is open.
                        Behavior on color {
                            ColorAnimation {
                                duration: Services.Motion.effectsFast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Services.Motion.standardCurve
                            }
                        }
                    }

                    // Hover (and click, for touch/keyboard users) arms the
                    // popup. Hover only OPENS — trayIdle decides when it
                    // closes, so travelling down into the popup never makes
                    // it disappear underneath the pointer.
                    MouseArea {
                        id: trayArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onContainsMouseChanged: if (containsMouse) pill.trayTouch()
                        onClicked: pill.trayTouch()
                    }
                }
            }

            Row {
                id: osdContent
                anchors.centerIn: parent
                spacing: 10
                opacity: pill.mode === "osd" ? 1 : 0
                visible: (pill.mode === "osd") || opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                Text {
                    font.family: Services.Fonts.family
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

                        // fill follows the level — the bounce spring makes
                        // each volume step land with a small overshoot
                        Behavior on width {
                            SpringAnimation { spring: Services.Motion.bounceSpring; damping: Services.Motion.bounceDamping }
                        }
                    }
                }
            }

            // pill morphs to show the latest notification for a few seconds, then
            // fades back to normalContent — identical mechanism to osdContent above,
            // just triggered by Services.Notifications instead of Volume/Brightness.
            // Column instead of Row so a long body wraps downward and pill.height
            // (bound to notificationContent.implicitHeight above) grows to fit it,
            // instead of eliding to one line.
            Column {
                id: notificationContent
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 4
                opacity: pill.mode === "notif" ? 1 : 0
                visible: (pill.mode === "notif") || opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                Row {
                    width: parent.width
                    spacing: 8

                    Text {
                        font.family: Services.Fonts.family
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
                        font.family: Services.Fonts.family
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width - 26
                        font.pixelSize: 13
                        font.bold: true
                        elide: Text.ElideRight
                        color: Services.Colors.text
                        text: pill.currentNotification ? pill.currentNotification.summary : ""
                    }
                }

                Text {
                    font.family: Services.Fonts.family
                    width: parent.width
                    visible: text.length > 0
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    font.pixelSize: 12
                    color: Services.Colors.accent
                    text: pill.currentNotification ? pill.currentNotification.body : ""
                }
            }

            // clicking the notification message runs its default action —
            // e.g. "Screenshot taken" → opens the shot in tensaku. Sibling
            // overlay on notificationContent, disabled whenever the pill has
            // morphed back so it can't eat clicks in other pill modes.
            MouseArea {
                anchors.fill: notificationContent
                enabled: pill.mode === "notif"
                cursorShape: Qt.PointingHandCursor
                onClicked: Services.Notifications.invokeDefault(pill.currentNotification)
            }

            // the REAL search input AND results list now live here, in the same
            // window as toplevel — one bar, many functions. Used to be just the
            // input, with results in a separate PopupWindow underneath (see git
            // history / launcherPopup, now removed); folded together so the pill
            // itself grows to show results, same idea as notificationContent.
            Column {
                id: launcherContent
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.margins: 12
                spacing: 8
                opacity: pill.mode === "launcher" ? 1 : 0
                visible: (pill.mode === "launcher") || opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                Row {
                    width: parent.width
                    height: 30
                    spacing: 8

                    Text {
                        font.family: Services.Fonts.family
                        text: "󰍉"
                        color: Services.Colors.text
                        font.pixelSize: 15
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    TextInput {
                        font.family: Services.Fonts.family
                        id: searchField
                        width: parent.width - 30
                        color: Services.Colors.text
                        font.pixelSize: 14
                        anchors.verticalCenter: parent.verticalCenter
                        onTextChanged: Services.Launcher.query = text

                        Keys.onPressed: (event) => {
                            // The delete confirm is modal: while it is up,
                            // every key belongs to it — typing included, so
                            // the query cannot change under the dialog.
                            if (Services.Launcher.confirmDelete) {
                                if (event.key === Qt.Key_Escape || event.key === Qt.Key_Delete) {
                                    Services.Launcher.confirmCancel()
                                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                    Services.Launcher.confirmAccept()
                                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up
                                        || event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                                    // two buttons: any arrow flips the pick
                                    Services.Launcher.confirmChoice = Services.Launcher.confirmChoice === 0 ? 1 : 0
                                }
                                event.accepted = true
                            } else if (event.key === Qt.Key_Delete) {
                                // Delete on a selected row opens the confirm;
                                // swallow it only when a dialog actually opened
                                // (settings rows have nothing to uninstall)
                                Services.Launcher.requestDelete()
                                event.accepted = Services.Launcher.confirmDelete
                            } else if (event.key === Qt.Key_Escape) {
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

                Text {
                    font.family: Services.Fonts.family
                    visible: Services.Launcher.results.length === 0
                    width: parent.width
                    height: 40
                    verticalAlignment: Text.AlignVCenter
                    color: Services.Colors.text
                    opacity: 0.6
                    font.pixelSize: 12
                    text: "No results"
                }

                ListView {
                    id: resultsList
                    width: parent.width
                    height: pill.launcherListHeight()
                    visible: Services.Launcher.results.length > 0
                    clip: true
                    model: Services.Launcher.results
                    currentIndex: Services.Launcher.selectedIndex

                    // same spring as the pill's own width/height Behaviors —
                    // list and container move in lockstep instead of the list
                    // snapping to its new size while the pill smoothly grows toward it
                    Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                    delegate: Rectangle {
                        width: resultsList.width
                        height: 44
                        radius: 8
                        // the selection is painted once by selPill below, not
                        // per row — two rows crossfading (old design) read as
                        // nothing on an all-dark theme; one moving block reads
                        // as the selection pouring from row to row
                        color: "transparent"

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
                                font.family: Services.Fonts.family
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

                    // One accent block for the whole list — it lives in
                    // content coordinates (parent = contentItem) so it rides
                    // every scroll for free and always sits under currentItem.
                    // The bounce spring is Motion.qml's own M3E slot for
                    // "indicator slides", and springs retarget with velocity:
                    // holding an arrow key pours continuously instead of
                    // restarting per row (this is the "colour pours from one
                    // selected to the other" behaviour).
                    Rectangle {
                        id: selPill
                        parent: resultsList.contentItem
                        z: -1
                        x: 0
                        y: resultsList.currentItem ? resultsList.currentItem.y : 0
                        width: resultsList.width
                        height: 44
                        radius: 8
                        visible: resultsList.currentItem != null
                        color: Services.Colors.accent

                        Behavior on y {
                            SpringAnimation {
                                spring: Services.Motion.bounceSpring
                                damping: Services.Motion.bounceDamping
                            }
                        }
                    }

                    // slim position rail — the list caps at 6 rows, so this
                    // is how you can see there is more below; it hides the
                    // moment everything fits. Same content-coords parent as
                    // selPill: y adds contentY back so the thumb stays pinned
                    // to the viewport while scrolling happens underneath it.
                    Rectangle {
                        id: listRail
                        parent: resultsList.contentItem
                        z: 1
                        readonly property bool scrollable: resultsList.contentHeight > resultsList.height
                        readonly property real trackH: resultsList.height - 8
                        readonly property real thumbH: Math.min(trackH, Math.max(20, resultsList.height * resultsList.height / Math.max(1, resultsList.contentHeight)))

                        x: resultsList.width - 6
                        y: resultsList.contentY + 4 + (scrollable
                            ? (resultsList.contentY / (resultsList.contentHeight - resultsList.height)) * (trackH - thumbH)
                            : 0)
                        width: 4
                        height: scrollable ? thumbH : 0
                        radius: 2
                        visible: scrollable
                        color: Services.Colors.accent
                        opacity: 0.55
                    }
                }
            }

            // Delete confirmation — sits OVER the list area instead of
            // swapping content, so the row that opened it stays visible
            // behind. confirmOverlayHeight() makes the overlay (and with it
            // the pill) at least as tall as the dialog box, so a short
            // search result can't crop it. Modal by construction: the
            // MouseArea swallows clicks (rows behind must not launch mid-
            // dialog) and searchField's key handler routes every key here
            // while visible.
            Rectangle {
                id: deleteConfirm
                visible: Services.Launcher.confirmDelete && pill.mode === "launcher"
                x: launcherContent.x
                y: launcherContent.y + 38    // search row (30) + Column spacing (8)
                width: launcherContent.width
                height: pill.confirmOverlayHeight()
                color: "transparent"
                z: 10

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.AllButtons
                    onPressed: (mouse) => mouse.accepted = true
                }

                Rectangle {   // the dialog box
                    anchors.centerIn: parent
                    width: parent.width - 16
                    height: deleteBody.implicitHeight + 26
                    radius: 10
                    color: Services.Colors.surface
                    border.width: 1
                    border.color: Services.Colors.accent

                    Column {
                        id: deleteBody
                        anchors.centerIn: parent
                        width: parent.width - 24
                        spacing: 12

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 10

                            IconImage {
                                implicitSize: 26
                                anchors.verticalCenter: parent.verticalCenter
                                source: Services.Launcher.confirmEntry && Services.Launcher.confirmEntry.icon !== ""
                                    ? Quickshell.iconPath(Services.Launcher.confirmEntry.icon, true) : ""
                            }

                            Column {
                                spacing: 2
                                anchors.verticalCenter: parent.verticalCenter

                                Text {
                                    font.family: Services.Fonts.family
                                    color: Services.Colors.accent
                                    font.pixelSize: 14
                                    font.bold: true
                                    text: Services.Launcher.confirmEntry ? Services.Launcher.confirmEntry.name : ""
                                }

                                Text {
                                    font.family: Services.Fonts.family
                                    color: Services.Colors.textMuted
                                    font.pixelSize: 11
                                    text: Services.Launcher.confirmEntry && Services.Launcher.isWebapp(Services.Launcher.confirmEntry)
                                        ? "web app — deletes this launcher"
                                        : "app — opens a terminal to uninstall"
                                }
                            }
                        }

                        Text {
                            font.family: Services.Fonts.family
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            color: Services.Colors.text
                            font.pixelSize: 12
                            text: Services.Launcher.confirmEntry && Services.Launcher.isWebapp(Services.Launcher.confirmEntry)
                                ? "Delete this web app?"
                                : "Uninstall this app?"
                        }

                        Row {
                            anchors.horizontalCenter: parent.horizontalCenter
                            spacing: 12

                            Rectangle {   // Yes
                                width: yesLabel.implicitWidth + 32
                                height: 30
                                radius: 8
                                color: Services.Launcher.confirmChoice === 0 ? Services.Colors.accent : "transparent"
                                border.width: Services.Launcher.confirmChoice === 0 ? 0 : 1
                                border.color: Services.Colors.accent

                                Text {
                                    font.family: Services.Fonts.family
                                    id: yesLabel
                                    anchors.centerIn: parent
                                    text: "Yes"
                                    font.pixelSize: 13
                                    font.bold: Services.Launcher.confirmChoice === 0
                                    color: Services.Colors.text
                                    opacity: Services.Launcher.confirmChoice === 0 ? 1 : 0.75
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.Launcher.confirmChoice = 0
                                        Services.Launcher.confirmAccept()
                                    }
                                }
                            }

                            Rectangle {   // No
                                width: noLabel.implicitWidth + 32
                                height: 30
                                radius: 8
                                color: Services.Launcher.confirmChoice === 1 ? Services.Colors.accent : "transparent"
                                border.width: Services.Launcher.confirmChoice === 1 ? 0 : 1
                                border.color: Services.Colors.accent

                                Text {
                                    font.family: Services.Fonts.family
                                    id: noLabel
                                    anchors.centerIn: parent
                                    text: "No"
                                    font.pixelSize: 13
                                    font.bold: Services.Launcher.confirmChoice === 1
                                    color: Services.Colors.text
                                    opacity: Services.Launcher.confirmChoice === 1 ? 1 : 0.75
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        Services.Launcher.confirmChoice = 1
                                        Services.Launcher.confirmAccept()
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // theme picker + power menu now live in modules/ instead of inline
            // here — same reasoning as the file getting long: the mode/size
            // logic (above) stays in Bar.qml, the actual markup moved out.
            PillThemeContent {
                anchors.margins: 12
                active: pill.mode === "theme"
            }

            PillWallpaperContent {
                anchors.margins: 12
                active: pill.mode === "wallpaper"
            }

            PillPowerContent {
                active: pill.mode === "power"
                onActionTriggered: (command) => {
                    powerProcess.command = command
                    powerProcess.running = true
                }
            }

            // clipboard history, extracted like theme/power: Bar keeps the
            // mode/size logic (above), the markup lives in modules/
            PillClipboardContent {
                id: clipboardContent
                anchors.margins: 12
                active: pill.mode === "clipboard"
            }

            // Control center folded in the same way — ControlCenterPanel is
            // already a self-contained 760x380 component (draws its own
            // background/radius), so no extraction needed, just center it
            // and gate its opacity by mode like everything else here.
            Item {
                anchors.fill: parent
                opacity: pill.mode === "controlcenter" ? 1 : 0
                visible: (pill.mode === "controlcenter") || opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                ControlCenterPanel {
                    anchors.centerIn: parent
                }
            }

            // Clock card folded in the same way — the pill itself morphs to
            // 620x520 (modes.clock) and ClockCardPopup centers inside it.
            // Replaces the old clockPopup PopupWindow: no separate window,
            // no anchor math, always drawn in the bar's own layer.
            Item {
                anchors.fill: parent
                opacity: pill.mode === "clock" ? 1 : 0
                visible: (pill.mode === "clock") || opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                ClockCardPopup {
                    anchors.centerIn: parent
                }
            }

        }

        // ---------------- activity chips ----------------
        // Tiny indicators beside the pill's right edge, in every rest state
        // (compact capsule included — the old rec/updates badges were only
        // reachable from the expanded row). Animation = slide-in from the
        // left: width grows from 0 while content is pulled left-to-right
        // under a clip, so each chip looks like it's drawn OUT of the bar;
        // when its condition clears it retracts back into the pill.
        Row {
            id: activityRow
            anchors.left: pill.right
            // 8px off the pill's edge — the tray chip is inside the pill
            // now, so no straddle compensation is needed
            anchors.leftMargin: 8
            anchors.verticalCenter: pill.verticalCenter
            spacing: 6
            // transient pill modes (launcher/cc/…) own the screen — the
            // chips only belong to the resting bar; fade them out with the
            // mode change instead of popping them off mid-morph
            opacity: pill.mode === "rest" ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: Services.Motion.effects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }

            // --- screen recording: pulsing red dot + elapsed ---
            Item {
                id: recChip
                readonly property bool active: Services.ScreenRecording.recording || Services.ScreenRecording.starting
                height: 26
                width: active ? recBody.width : 0
                opacity: active ? 1 : 0
                visible: active || opacity > 0.01
                clip: true
                anchors.verticalCenter: parent.verticalCenter

                Behavior on width { SpringAnimation { spring: Services.Motion.spatialFastSpring; damping: Services.Motion.spatialFastDamping } }
                Behavior on opacity { NumberAnimation { duration: Services.Motion.medium1; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                Item {
                    id: recInner
                    height: parent.height
                    width: recBody.width
                    x: recChip.active ? 0 : -16
                    Behavior on x { SpringAnimation { spring: Services.Motion.popSpring; damping: Services.Motion.popDamping } }

                    Rectangle {
                        id: recBody
                        height: 26
                        radius: 13
                        // Was Qt.rgba(0.88, 0.38, 0.38, 0.18) — an 18% wash.
                        // Two things were wrong with that: (1) 18% red laid
                        // over the pill's dark background desaturates into a
                        // barely-there tint that reads as a rendering bug, not
                        // a recording, and (2) the text was Colors.critical
                        // on a red wash — red on red, ~2.5:1. The sibling
                        // media/updates chips are solid Colors.surface, so
                        // this is solid too: the colour IS the signal, and
                        // white text on Colors.critical (#e74c3c, L≈0.22)
                        // comes out ~3.8:1 instead of 2.5:1. Only visible
                        // while recording, so the saturation is earned.
                        color: Services.Colors.critical
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.22)
                        width: recRow.implicitWidth + 18

                        Row {
                            id: recRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                font.family: Services.Fonts.family
                                id: recDot
                                text: "●"
                                font.pixelSize: 9
                                color: "#ffffff"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                font.family: Services.Fonts.family
                                text: (Services.ScreenRecording.starting && !Services.ScreenRecording.recording)
                                    ? "Starting…" : Services.ScreenRecording.elapsedDisplay
                                font.pixelSize: 11
                                font.bold: true
                                color: "#ffffff"
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.ScreenRecording.toggle()
                        }
                    }
                }

                // heartbeat pulse while rolling
                SequentialAnimation {
                    loops: Animation.Infinite
                    running: Services.ScreenRecording.recording
                    NumberAnimation { target: recDot; property: "opacity"; to: 0.25; duration: 550; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.standardCurve }
                    NumberAnimation { target: recDot; property: "opacity"; to: 1; duration: 550; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.standardDecelerate }
                }
            }

            // --- media: app icon + position; click opens the card ---
            Item {
                id: mediaChip
                property bool expanded: false
                readonly property bool active: Services.Media.hasPlayer
                height: 26
                width: active ? mediaBody.width : 0
                opacity: active ? 1 : 0
                visible: active || opacity > 0.01
                clip: true
                anchors.verticalCenter: parent.verticalCenter

                Behavior on width { SpringAnimation { spring: Services.Motion.spatialFastSpring; damping: Services.Motion.spatialFastDamping } }
                Behavior on opacity { NumberAnimation { duration: Services.Motion.medium1; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                Item {
                    id: mediaInner
                    height: parent.height
                    width: mediaBody.width
                    x: mediaChip.active ? 0 : -16
                    Behavior on x { SpringAnimation { spring: Services.Motion.popSpring; damping: Services.Motion.popDamping } }

                    Rectangle {
                        id: mediaBody
                        height: 26
                        radius: 13
                        color: Services.Colors.surface
                        width: mediaRow.implicitWidth + 18

                        Row {
                            id: mediaRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                font.family: Services.Fonts.family
                                // paused swaps the icon for the pause glyph —
                                // hasPlayer covers playing OR paused
                                text: Services.Media.playing ? Services.Media.appIcon : "󰏤"
                                font.pixelSize: 12
                                color: Services.Colors.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                font.family: Services.Fonts.family
                                text: Services.Media.formatTime(Services.Media.position)
                                font.pixelSize: 11
                                font.bold: true
                                color: Services.Colors.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: mediaChip.expanded = !mediaChip.expanded
                        }
                    }
                }
            }

            // --- updates: monthly nudge chip (gate lives in Updates.qml) ---
            Item {
                id: updatesChip
                readonly property bool active: Services.Updates.showNudge
                height: 26
                width: active ? updatesBody.width : 0
                opacity: active ? 1 : 0
                visible: active || opacity > 0.01
                clip: true
                anchors.verticalCenter: parent.verticalCenter

                Behavior on width { SpringAnimation { spring: Services.Motion.spatialFastSpring; damping: Services.Motion.spatialFastDamping } }
                Behavior on opacity { NumberAnimation { duration: Services.Motion.medium1; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                Item {
                    id: updatesInner
                    height: parent.height
                    width: updatesBody.width
                    x: updatesChip.active ? 0 : -16
                    Behavior on x { SpringAnimation { spring: Services.Motion.popSpring; damping: Services.Motion.popDamping } }

                    Rectangle {
                        id: updatesBody
                        height: 26
                        radius: 13
                        color: Services.Colors.surface
                        width: updatesRow.implicitWidth + 18

                        Row {
                            id: updatesRow
                            anchors.centerIn: parent
                            spacing: 5

                            Text {
                                font.family: Services.Fonts.family
                                text: "󰚰"
                                font.pixelSize: 12
                                color: Services.Colors.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                font.family: Services.Fonts.family
                                text: Services.Updates.count > 9 ? "9+ updates"
                                    : Services.Updates.count + (Services.Updates.count === 1 ? " update" : " updates")
                                font.pixelSize: 11
                                font.bold: true
                                color: Services.Colors.text
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Updates.toggle()
                        }
                    }
                }
            }

        }

        // tiny IPC hook so the card can be toggled from binds/scripts (and
        // verified without a pointer): qs ipc call media toggle
        IpcHandler {
            target: "media"
            function toggle(): void { mediaChip.expanded = !mediaChip.expanded }
            function isExpanded(): bool { return mediaChip.expanded }
            function hasPlayer(): bool { return mediaChip.active }
        }

        // same trick for the tray popup — the whole feature is hover-driven,
        // so this is the only way to exercise it without a pointer:
        //   qs ipc call tray open / close / isOpen / count
        IpcHandler {
            target: "tray"
            function open(): void { pill.trayTouch() }
            function close(): void { pill.trayOpen = false }
            function isOpen(): bool { return pill.trayOpen }
            function count(): int { return SystemTray.items.values.length }
        }

        // ---------------- tray popup (Meet-style bounce) ----------------
        // The tray icons moved out of the pill and into this drop-down,
        // because that is what a down-chevron promises. Modeled on Google
        // Meet's reaction bar: hover the chevron and the panel springs in
        // with a bounce, the icons cascade in behind it, and the whole thing
        // retires on its own if you stop hovering (pill.trayIdle).
        //
        // The bar is the TOP layer, so Meet's upward pop is mirrored here —
        // this drops DOWN out of the pill, and the chevron flips to point
        // back up at it while open.
        PopupWindow {
            id: trayPopup
            anchor.window: toplevel
            // Centred on the chevron. trayChip sits at the pill's right edge
            // and the pill is horizontally centred, so its centre in toplevel
            // coords is (W + pillW)/2 - rightMargin - chipW/2 — the same
            // arithmetic recordingPopup does. Clamped both ways because a
            // long tray row centred that far right would run off the screen.
            // mapFromItem() is avoided on purpose: the Quickshell docs say it
            // does NOT update reactively.
            anchor.rect.x: Math.max(12, Math.min(
                toplevel.width - trayCard.width - 12,
                (toplevel.width + pill.width) / 2 - 12 - trayChip.width / 2
                    - trayCard.width / 2))
            anchor.rect.y: pill.height + 4
            // Sized to the card EXACTLY. PopupWindow has no `mask` property
            // (checked the v0.3.1 type docs — only parentWindow, visible,
            // grabFocus, anchor, relativeX/Y, screen), so every pixel of this
            // surface is a click target: any transparent padding would be a
            // dead zone that swallows clicks aimed at the desktop.
            implicitWidth: trayCard.width
            implicitHeight: trayCard.height
            color: "transparent"

            // same animate-then-hide window pattern as mediaPopup /
            // recordingPopup / updatesPopup: show instantly on open, let the
            // card spring, and wait out the exit before the surface goes away
            property bool windowVisible: false
            visible: windowVisible

            Connections {
                target: pill
                function onTrayOpenChanged() {
                    if (pill.trayOpen) {
                        trayClose.stop()
                        // pulse visible off→on for a FRESH map every open:
                        // guards the stale-open state where Hyprland
                        // suppressed the popup under a fullscreen client, QML
                        // thought it was shown, and it never recovered.
                        trayPopup.windowVisible = false
                        trayMapPulse.restart()
                    } else {
                        trayClose.restart()
                    }
                }
            }

            Timer {
                id: trayMapPulse
                interval: 30
                onTriggered: trayPopup.windowVisible = true
            }

            Timer {
                id: trayClose
                interval: 270
                onTriggered: if (!pill.trayOpen) trayPopup.windowVisible = false
            }

            Rectangle {
                id: trayCard
                // Width has to consider BOTH states: with no tray applet the
                // icon Row collapses to 0 and this would be a bare 18px
                // lozenge, so it takes whichever of the row or the
                // "No tray apps" hint is wider. (+18 = the card's padding.)
                width: Math.max(trayRow.implicitWidth, trayEmptyHint.implicitWidth) + 18
                height: 44
                radius: 22
                color: Services.Colors.surface
                border.width: 1
                border.color: Services.Colors.low

                // Empty state — this machine has no tray applet at all, so
                // this is currently what anyone hovering the chevron gets.
                // Without it the arrow would look broken rather than merely
                // pending content.
                Text {
                    font.family: Services.Fonts.family
                    id: trayEmptyHint
                    anchors.centerIn: parent
                    visible: SystemTray.items.values.length === 0
                    text: "No tray apps"
                    font.pixelSize: 11
                    color: Services.Colors.textMuted
                }

                // The bounce. Grows out of its own top edge — the edge that
                // touches the bar — so it reads as emerging from the chevron
                // rather than inflating in place. bounceSpring carries M3E's
                // ~12% overshoot, which is the whole effect; opacity rides
                // the effects token instead (M3: effects never overshoot).
                // No y-slide: the surface is exactly card-height, so any
                // upward offset would clip the card against the top edge.
                transformOrigin: Item.Top
                scale: pill.trayOpen ? 1 : 0.6
                opacity: pill.trayOpen ? 1 : 0

                Behavior on scale {
                    SpringAnimation {
                        spring: Services.Motion.bounceSpring
                        damping: Services.Motion.bounceDamping
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }

                // HoverHandler, not a MouseArea: the icons underneath need
                // their own mouse areas, and a MouseArea over the card would
                // eat them. HoverHandler observes without consuming.
                HoverHandler {
                    onHoveredChanged: if (hovered) pill.trayTouch()
                }

                Row {
                    id: trayRow
                    anchors.centerIn: parent
                    // mutually exclusive with trayEmptyHint — both are
                    // centre-anchored, so if both showed they'd overlap
                    visible: SystemTray.items.values.length > 0
                    spacing: 2

                    Repeater {
                        model: SystemTray.items

                        delegate: Item {
                            id: trayIconItem
                            required property int index
                            required property var modelData

                            // 32px plate, not the 18px icon: the tray row is
                            // now a touch target the pointer has to travel to,
                            // so it gets Meet's generous circular hit area.
                            width: 32
                            height: 32

                            // Meet's per-emoji hover disc
                            Rectangle {
                                anchors.fill: parent
                                radius: width / 2
                                color: trayIconArea.containsMouse
                                    ? Services.Colors.surfaceAlt : "transparent"
                                // ColorAnimation, not NumberAnimation: the
                                // rest value here is "transparent", and
                                // NumberAnimation coerced it to #000000 —
                                // which is why every tray icon sat on a solid
                                // black 32px disc instead of an invisible plate
                                // that only darkens on hover.
                                Behavior on color {
                                    ColorAnimation {
                                        duration: Services.Motion.effectsFast
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Services.Motion.standardCurve
                                    }
                                }
                            }

                            IconImage {
                                anchors.centerIn: parent
                                width: 18
                                height: 18
                                source: modelData.icon
                            }

                            // Cascade: each icon pops in on Motion's stagger
                            // so the row unfurls instead of appearing at once.
                            //
                            // The stagger is a PauseAnimation, NOT a `delay:`
                            // on the animation itself — QQuickAnimation,
                            // NumberAnimation and SpringAnimation have no
                            // `delay` property at all (SpringAnimation's are
                            // only damping/epsilon/mass/modulus/spring/
                            // velocity), and assigning one throws "Cannot
                            // assign to non-existent property" and takes the
                            // whole config down. The Behavior docs point at
                            // exactly this shape: "To provide multiple
                            // animations within a Behavior, use
                            // ParallelAnimation or SequentialAnimation."
                            //
                            // The pause length is BOUND to trayOpen rather
                            // than baked in, so the close has no stagger — a
                            // cascading fade-out would outlive the 270ms
                            // surface close.
                            opacity: pill.trayOpen ? 1 : 0
                            scale: pill.trayOpen ? 1 : 0.45
                            transformOrigin: Item.Center
                            Behavior on opacity {
                                SequentialAnimation {
                                    PauseAnimation {
                                        duration: pill.trayOpen
                                            ? Services.Motion.staggerDelay(index) : 0
                                    }
                                    NumberAnimation {
                                        duration: Services.Motion.effects
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                    }
                                }
                            }
                            Behavior on scale {
                                SequentialAnimation {
                                    PauseAnimation {
                                        duration: pill.trayOpen
                                            ? Services.Motion.staggerDelay(index) : 0
                                    }
                                    SpringAnimation {
                                        spring: Services.Motion.popSpring
                                        damping: Services.Motion.popDamping
                                    }
                                }
                            }

                            // left = activate, middle = secondary activate,
                            // right = the app's own menu (DBusMenu →
                            // QsMenuAnchor). Activating closes the popup;
                            // opening a menu deliberately does not, since the
                            // menu is anchored to the icon inside it.
                            MouseArea {
                                id: trayIconArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                                onContainsMouseChanged: if (containsMouse) pill.trayTouch()
                                onClicked: (mouse) => {
                                    if (mouse.button === Qt.RightButton) {
                                        if (modelData.hasMenu && modelData.menu && modelData.menu.menu) {
                                            trayMenuAnchor.anchor.item = trayIconItem
                                            trayMenuAnchor.menu = modelData.menu.menu
                                            trayMenuAnchor.open()
                                        }
                                    } else if (mouse.button === Qt.MiddleButton) {
                                        modelData.secondaryActivate()
                                        pill.trayOpen = false
                                    } else {
                                        modelData.activate()
                                        pill.trayOpen = false
                                    }
                                }
                            }

                            QsMenuAnchor {
                                id: trayMenuAnchor
                                // anchor.item + menu are set per-click above
                            }
                        }
                    }
                }
            }
        }

        // full media card — anchored under the media activity chip, so it
        // hangs off wherever that chip currently sits
        PopupWindow {
            id: mediaPopup
            anchor.window: toplevel
            // activityRow sits in toplevel coordinates (anchored to pill.right),
            // mediaChip.x is its Row slot — summing the two tracks reactively,
            // unlike mapFromItem() which the Quickshell docs say does NOT
            // update reactively
            anchor.rect.x: activityRow.x + mediaChip.x
            anchor.rect.y: pill.height + 4
            implicitWidth: 480
            implicitHeight: 220
            color: "transparent"

            // standard animate-then-hide window pattern (settingsPopup,
            // recordingPopup, updatesPopup, advPanel all do this): the
            // window shows instantly on open, mediaSizer springs the card
            // out of the middle, and closing waits 270ms so the exit
            // animation plays before the surface goes away.
            property bool windowVisible: false
            visible: windowVisible

            Connections {
                target: mediaChip
                function onExpandedChanged() {
                    if (mediaChip.expanded) {
                        mediaClose.stop()
                        // pulse visible off→on: forces a FRESH map every
                        // open. Guards against the stale-open state where
                        // Hyprland suppressed the popup under a fullscreen
                        // client — QML thought it was shown, compositor
                        // never mapped it, and it never recovered.
                        mediaPopup.windowVisible = false
                        mapPulse.restart()
                    } else {
                        mediaClose.restart()
                    }
                }
            }

            Timer {
                id: mapPulse
                interval: 30
                onTriggered: mediaPopup.windowVisible = true
            }

            Timer {
                id: mediaClose
                interval: 270
                onTriggered: {
                    if (!mediaChip.expanded)
                        mediaPopup.windowVisible = false
                }
            }

            Item {
                id: mediaSizer
                anchors.centerIn: parent
                clip: true
                width:  mediaChip.expanded ? 480 : 0
                height: mediaChip.expanded ? 220 : 0

                Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
                Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

            Rectangle {
                id: mediaCard
                width: 480
                height: 220
                anchors.centerIn: parent
                color: Services.Colors.surface
                radius: 16
                // same elevated-card language as the settings powercard:
                // tonal surface + hairline outline. the old blurred-art
                // backdrop + double gradient sat on top of the cava wave
                // and read like a different shell — flat keeps it one
                // system with the tray/CC popups
                border.width: 1
                border.color: Services.Colors.low

                Column {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 16

                    // header — art thumb, title/artist, app glyph
                    Row {
                        width: parent.width
                        height: 72
                        spacing: 12

                        Rectangle {
                            id: artFrame
                            width: 72
                            height: 72
                            radius: 12
                            color: Services.Colors.surfaceAlt
                            clip: true
                            anchors.verticalCenter: parent.verticalCenter

                            Image {
                                anchors.fill: parent
                                source: Services.Media.artUrl
                                visible: Services.Media.artUrl !== ""
                                fillMode: Image.PreserveAspectCrop
                                smooth: true
                                asynchronous: true
                            }

                            Text {
                                font.family: Services.Fonts.family
                                anchors.centerIn: parent
                                visible: Services.Media.artUrl === ""
                                text: "\uf385"
                                font.pixelSize: 24
                                color: Services.Colors.textMuted
                            }
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 84
                            spacing: 5

                            Row {
                                width: parent.width
                                spacing: 8

                                Text {
                                    font.family: Services.Fonts.family
                                    width: Math.max(0, parent.width - appGlyph.width - 8)
                                    elide: Text.ElideRight
                                    verticalAlignment: Text.AlignVCenter
                                    text: Services.Media.title
                                    color: Services.Colors.text
                                    font.pixelSize: 15
                                    font.bold: true
                                }

                                Text {
                                    font.family: Services.Fonts.family
                                    id: appGlyph
                                    text: Services.Media.appIcon
                                    color: Services.Colors.accent
                                    font.pixelSize: 14
                                    anchors.verticalCenter: parent.verticalCenter
                                }
                            }

                            Text {
                                font.family: Services.Fonts.family
                                width: parent.width
                                elide: Text.ElideRight
                                text: Services.Media.artist
                                color: Services.Colors.textMuted
                                font.pixelSize: 12
                            }
                        }
                    }

                    // progress — elapsed/total flank a seekable track
                    Row {
                        width: parent.width
                        height: 16
                        spacing: 10

                        Text {
                            font.family: Services.Fonts.family
                            anchors.verticalCenter: parent.verticalCenter
                            text: Services.Media.formatTime(Services.Media.position)
                            color: Services.Colors.textMuted
                            font.pixelSize: 10
                        }

                        Item {
                            id: track
                            width: parent.width - 92
                            height: 16
                            anchors.verticalCenter: parent.verticalCenter

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width
                                height: 6
                                radius: 3
                                color: Qt.rgba(Services.Colors.textMuted.r, Services.Colors.textMuted.g,
                                               Services.Colors.textMuted.b, 0.18)
                            }

                            Rectangle {
                                id: trackFill
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width * (Services.Media.length > 0
                                        ? Services.Media.position / Services.Media.length : 0)
                                height: 6
                                radius: 3
                                color: Services.Colors.accent

                                // linear 1s glide — position ticks every
                                // second, this turns the tick into motion
                                Behavior on width {
                                    NumberAnimation {
                                        duration: 1000
                                        easing.type: Easing.Linear
                                    }
                                }
                            }

                            Rectangle {
                                id: trackThumb
                                anchors.verticalCenter: parent.verticalCenter
                                x: Math.max(5, trackFill.width - 5)
                                width: 10
                                height: 10
                                radius: 5
                                color: Services.Colors.accent
                                scale: trackMa.containsMouse ? 1.4 : 1
                                Behavior on scale {
                                    SpringAnimation {
                                        spring: Services.Motion.spatialFastSpring
                                        damping: Services.Motion.spatialFastDamping
                                    }
                                }
                            }

                            MouseArea {
                                id: trackMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Media.seek(mouse.x / width)
                            }
                        }

                        Text {
                            font.family: Services.Fonts.family
                            anchors.verticalCenter: parent.verticalCenter
                            text: Services.Media.formatTime(Services.Media.length)
                            color: Services.Colors.textMuted
                            font.pixelSize: 10
                        }
                    }

                    // transport — hover glides on the tonal circles
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 28

                        Rectangle {
                            id: prevBtn
                            width: 40
                            height: 40
                            radius: 20
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                           Services.Colors.text.b, prevMa.containsMouse ? 0.16 : 0.08)
                            Behavior on color {
                                ColorAnimation {
                                    duration: Services.Motion.effectsFast
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                }
                            }
                            scale: prevMa.pressed ? 0.9 : 1
                            Behavior on scale {
                                SpringAnimation {
                                    spring: Services.Motion.popSpring
                                    damping: Services.Motion.popDamping
                                }
                            }

                            Text {
                                font.family: Services.Fonts.family
                                anchors.centerIn: parent
                                text: "\uf4ae"
                                font.pixelSize: 17
                                color: Services.Colors.text
                            }

                            MouseArea {
                                id: prevMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Media.previous()
                            }
                        }

                        Rectangle {
                            id: playBtn
                            width: 48
                            height: 48
                            radius: 24
                            anchors.verticalCenter: parent.verticalCenter
                            color: Services.Colors.accent
                            scale: playMa.pressed ? 0.9 : 1
                            Behavior on scale {
                                SpringAnimation {
                                    spring: Services.Motion.popSpring
                                    damping: Services.Motion.popDamping
                                }
                            }

                            Text {
                                font.family: Services.Fonts.family
                                anchors.centerIn: parent
                                text: Services.Media.playing ? "\uf447" : "\uf44a"
                                font.pixelSize: 20
                                color: Services.Colors.background
                            }

                            MouseArea {
                                id: playMa
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Media.togglePlay()
                            }
                        }

                        Rectangle {
                            id: nextBtn
                            width: 40
                            height: 40
                            radius: 20
                            anchors.verticalCenter: parent.verticalCenter
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                           Services.Colors.text.b, nextMa.containsMouse ? 0.16 : 0.08)
                            Behavior on color {
                                ColorAnimation {
                                    duration: Services.Motion.effectsFast
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                }
                            }
                            scale: nextMa.pressed ? 0.9 : 1
                            Behavior on scale {
                                SpringAnimation {
                                    spring: Services.Motion.popSpring
                                    damping: Services.Motion.popDamping
                                }
                            }

                            Text {
                                font.family: Services.Fonts.family
                                anchors.centerIn: parent
                                text: "\uf4b1"
                                font.pixelSize: 17
                                color: Services.Colors.text
                            }

                            MouseArea {
                                id: nextMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.Media.next()
                            }
                        }
                    }
                }
            }
            } // mediaSizer

            HyprlandFocusGrab {
                windows: [mediaPopup]
                active: mediaChip.expanded
                onCleared: mediaChip.expanded = false
            }
        }

        // Advanced side panel — docks to the right of the pill. Same
        // animate-then-hide pattern, driven by advancedPanel. Separate
        // window because it needs real room for pair/trust/forget controls
        // that don't fit in a tile-sized popover.
        PopupWindow {
            id: controlCenterAdvancedPopup
            anchor.window: toplevel
            // Docks to the LEFT of the pill now, using pill.x directly —
            // Qt's own computed position from the anchors, rather than
            // re-deriving "center + half-width" by hand. The hand-derived
            // version was the likely cause of "doesn't follow": it assumed
            // pill.width had already settled to its final controlcenter
            // value (760) at the moment this binding was read, but pill.x
            // is the actual live position regardless of what's mid-animation.
            anchor.rect.x: pill.x - 260 - 12
            // pill.y (top of the pill), not pill.height + 4 (below the whole
            // pill). Every other popup wants "below the pill" since the pill
            // is short for their triggers (osd/rest height). Control center
            // is different: the pill itself IS the 380px-tall panel now, so
            // "below it" meant "below the entire panel", landing at the
            // bottom instead of running alongside it.
            anchor.rect.y: pill.y
            implicitWidth: 260
            implicitHeight: 380
            color: "transparent"

            property bool windowVisible: false
            visible: windowVisible

            Connections {
                target: Services.ControlCenter
                function onAdvancedPanelChanged() {
                    if (Services.ControlCenter.advancedPanel !== ""
                        && toplevel.ownsOverlay(Services.ControlCenter)) {
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

                // "open" isn't one fixed size anymore — audio/network/bluetooth
                // now share this window (see ControlCenterAdvanced.qml), and
                // audio's list is usually much shorter. advPanel.height reads
                // the content's own live-computed height (same "content
                // decides size, container follows" idea as the pill's notif
                // and launcher modes) instead of a number hardcoded here.
                readonly property string mode: Services.ControlCenter.advancedPanel !== "" ? "open" : "closed"
                readonly property var modes: ({
                    open:   () => Qt.size(260, advPanel.height),
                    closed: () => Qt.size(0, 0)
                })
                readonly property size targetSize: (modes[mode] || modes.closed)()
                width:  targetSize.width
                height: targetSize.height

                Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
                Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                ControlCenterAdvanced {
                    id: advPanel
                    anchors.centerIn: parent
                }
            }
        }

        // Recording popup — anchor to rightGroup's left edge (shifted left
        // by the in-pill tray slot).
        PopupWindow {
            id: recordingPopup
            anchor.window: toplevel
            anchor.rect.x: (toplevel.width + pill.width) / 2 - 12 - pill.traySlot - rightGroup.width
            anchor.rect.y: pill.height + 4
            implicitWidth: 260
            implicitHeight: 300
            color: "transparent"

            property bool windowVisible: false
            visible: windowVisible

            Connections {
                target: Services.ScreenRecording
                function onOpenChanged() {
                    if (toplevel.ownsOverlay(Services.ScreenRecording)) {
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

                Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
                Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                ScreenRecordingPopup {
                    anchors.centerIn: parent
                }
            }
        }

        HyprlandFocusGrab {
            windows: [recordingPopup]
            active: toplevel.ownsOverlay(Services.ScreenRecording)
            onCleared: Services.ScreenRecording.close()
        }

        // Updates popup — hangs under the updates activity chip, same
        // anchoring pattern as mediaPopup (activityRow lives in toplevel
        // coordinates, chip.x is its Row slot).
        PopupWindow {
            id: updatesPopup
            anchor.window: toplevel
            anchor.rect.x: activityRow.x + updatesChip.x
            anchor.rect.y: pill.height + 4
            implicitWidth: 280
            implicitHeight: 380
            color: "transparent"

            property bool windowVisible: false
            visible: windowVisible

            Connections {
                target: Services.Updates
                function onOpenChanged() {
                    if (toplevel.ownsOverlay(Services.Updates)) {
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

                Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
                Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                UpdatesPopup {
                    anchors.centerIn: parent
                }
            }
        }

        HyprlandFocusGrab {
            windows: [updatesPopup]
            active: toplevel.ownsOverlay(Services.Updates)
            onCleared: Services.Updates.close()
        }

        HyprlandFocusGrab {
            // clock card lives inside the pill (inside toplevel) now —
            // same pattern as the ControlCenter/PowerMenu grabs.
            windows: [toplevel]
            active: toplevel.ownsOverlay(Services.ClockCard)
            onCleared: Services.ClockCard.close()
        }

        HyprlandFocusGrab {
            // toplevel instead of the old controlCenterPopup — the panel
            // lives inside the pill (inside toplevel) now. Same pattern as
            // the PowerMenu grab below, which faced this exact change earlier.
            windows: [toplevel, controlCenterAdvancedPopup]
            active: toplevel.ownsOverlay(Services.ControlCenter)
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
            active: toplevel.ownsOverlay(Services.PowerMenu)
            onCleared: Services.PowerMenu.open = false
        }

        // Settings app — its own centered card window instead of a pill
        // morph: this is document-scale UI with a sidebar, and the launcher
        // deep-links into it (SettingsApp.page/focusId). toplevel only ever
        // grows with the pill (max 560), so vertical centering anchors to
        // the screen; the sizer springs make it open and close in place.
        PopupWindow {
            id: settingsPopup
            anchor.window: toplevel
            anchor.rect.x: (toplevel.width - settingsSizer.width) / 2
            anchor.rect.y: ((toplevel.screen ? toplevel.screen.height : 900) - settingsSizer.height) / 2
            implicitWidth: 1000
            implicitHeight: 640
            color: "transparent"

            property bool windowVisible: false
            visible: windowVisible

            Connections {
                target: Services.SettingsApp
                function onOpenChanged() {
                    if (toplevel.ownsOverlay(Services.SettingsApp)) {
                        settingsClose.stop()
                        settingsPopup.windowVisible = true
                    } else {
                        settingsClose.restart()
                    }
                }
            }

            Timer {
                id: settingsClose
                interval: 270
                onTriggered: {
                    if (!Services.SettingsApp.open)
                        settingsPopup.windowVisible = false
                }
            }

            // workspace stickiness — settings lives on workspace 1, so
            // leaving that workspace closes it. Hide only, never force a
            // workspace switch back (that would fight the user).
            Connections {
                target: Hyprland
                function onFocusedWorkspaceChanged() {
                    if (Services.SettingsApp.open
                        && Hyprland.focusedWorkspace
                        && Hyprland.focusedWorkspace.id !== 1)
                        Services.SettingsApp.hide()
                }
            }

            Item {
                id: settingsSizer
                anchors.centerIn: parent
                clip: true

                width:  Services.SettingsApp.open ? 1000 : 0
                height: Services.SettingsApp.open ? 640 : 0

                Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
                Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                SettingsWindow {
                    id: settingsWin
                    anchors.centerIn: parent
                }
            }

            onVisibleChanged: if (visible) settingsWin.forceActiveFocus()
        }

        HyprlandFocusGrab {
            windows: [settingsPopup]
            active: toplevel.ownsOverlay(Services.SettingsApp)
            onCleared: Services.SettingsApp.hide()
        }
    }
}
