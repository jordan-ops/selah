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
    id: barRoot
    model: Quickshell.screens

    // Bar visibility flag, bound to shell.qml's barVisible (SUPER+H /
    // `qs ipc call bar toggle`) — one shared flag for every screen's bar.
    property bool barVisible: true

    // Requested when a panel is asked for while the bar is hidden (keybind
    // / IPC): shell.qml flips barVisible back on. An in-file assignment to
    // barVisible from here would clobber the binding shell pushes in.
    signal unhideRequested()

    // Forces services/Screensaver.qml to instantiate with the shell — its
    // IdleMonitor must be alive from startup for the 150 s idle trigger to
    // fire, and nothing else in the UI references that singleton.
    readonly property var screensaver: {
        const s = Services.Screensaver
        // the member access is what actually instantiates the singleton —
        // a bare type reference on its own stays a lazy component
        return s.idleSeconds >= 0 ? s : null
    }

    PanelWindow{
        id: toplevel
        required property var modelData
        screen: modelData
        // shell.qml's barVisible (SUPER+H / `qs ipc call bar toggle`).
        // false unmaps the layer surface entirely — Hyprland releases the
        // exclusive zone with it, so windows reflow into the freed strip.
        visible: barRoot.barVisible

        // Hiding the bar also closes whatever the pill had open: an
        // unmapped card can't receive its click-away or Escape, and the
        // remaining focus grabs would clear on unmap anyway — closing some
        // panels but not the media/updates/recording cards. Explicit and
        // uniform instead of grab-dependent. Polkit is deliberately left
        // up: a pending auth prompt is modal (dismissPanels won't touch it
        // either) and should still be there to answer after the bar
        // returns.
        Connections {
            target: barRoot
            function onBarVisibleChanged() {
                if (!barRoot.barVisible) {
                    pill.trayOpen = false   // chevron popup is its own surface
                    let guard = 0
                    while (!Services.Polkit.open && toplevel.panelOpen && guard++ < 16)
                        toplevel.dismissPanels()
                }
            }
        }

        // Asking for a panel while the bar is hidden (keybind/IPC): the
        // pill is the only surface that can show it, so bring the bar back
        // rather than leaving the panel open-but-invisible. Transient pill
        // modes (osd/notif) aren't in panelOpen — they clear themselves and
        // don't get to pop the bar back up.
        onPanelOpenChanged: if (panelOpen && !barRoot.barVisible) barRoot.unhideRequested()
        WlrLayershell.layer: (pill.osdVisible || pill.notifVisible || Services.Launcher.open || Services.Themes.open || Services.Wallpapers.open || Services.ControlCenter.open || Services.ClockCard.open || Services.Clipboard.open || Services.PowerMenu.open || Services.SettingsApp.open || Services.Polkit.open || Services.Media.open || Services.Updates.open || Services.ScreenRecording.open) ? WlrLayer.Overlay : WlrLayer.Top
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
        // through to the windows behind. The chips (updates/rec) live just
        // past the pill's right edge — they need their own combined region
        // or their MouseAreas are click-through. Media used to be a chip
        // here too; it moved inside the pill as MediaVisualiser, covered
        // by the pill's own region. Child regions with
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
            || toplevel.ownsOverlay(Services.PowerMenu) || toplevel.ownsOverlay(Services.Polkit)
            || toplevel.ownsOverlay(Services.Media) || toplevel.ownsOverlay(Services.Updates)
            || toplevel.ownsOverlay(Services.ScreenRecording)

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
            if (Services.Media.open)        { Services.Media.close(); return }
            if (Services.Updates.open)        { Services.Updates.close(); return }
            if (Services.ScreenRecording.open){ Services.ScreenRecording.close(); return }
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
        // ClockCard (taskInput) and SettingsApp (search / password / editors)
        // were later found missing here too — same bug class. ClockCard keeps
        // its entry but must NOT also arm a HyprlandFocusGrab: grab +
        // Exclusive on one surface made Hyprland finish the seat grab the
        // moment the exclusive commit landed, so the popup closed itself
        // right after opening (see the note where its grab used to be).
        // SettingsApp deliberately NOT in this predicate: the settings
        // window is settingsPopup (its own xdg_popup), not the pill —
        // adding it here made the BAR surface Exclusive while the settings
        // HyprlandFocusGrab whitelists only [settingsPopup], so keyboard
        // landed outside the grab set, the grab cleared instantly, and
        // onCleared hid the window the moment it opened ("settings closes
        // itself"). Settings keyboard comes from that grab alone (Sep 24
        // behavior). ClockCard stays because its grab IS [toplevel].
        // Polkit joins for the same reason ClockCard is here: the password
        // field lives in the pill (bar surface) now, so the bar must be
        // Exclusive while an auth request is pending or the field can
        // never receive keys — same recipe as the launcher's search field.
        // Updates + recording join for the media card's reason: no text
        // field, but the pill still needs Exclusive so its Keys handler
        // receives Escape — their FocusGrabs are gone (grab + Exclusive
        // on one surface is the fight described above).
        WlrLayershell.keyboardFocus: (Services.Launcher.open || Services.Themes.open || Services.Wallpapers.open || Services.Clipboard.open || Services.ClockCard.open || Services.Polkit.open || Services.Media.open || Services.Updates.open || Services.ScreenRecording.open) ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // Live global geometry of the pill — pushed into services/BarMetrics
        // for EdgeLight's orbit glow (and re-pushed whenever the pill
        // morphs, the tray slot changes or content width moves it).
        readonly property rect pillGlobal: Qt.rect(
            (toplevel.screen.x ?? 0) + pill.x,
            (toplevel.screen.y ?? 0) + pill.y,
            pill.width, pill.height)
        function publishPill() {
            Services.BarMetrics.update(modelData.name, {
                x: pillGlobal.x, y: pillGlobal.y,
                w: pillGlobal.width, h: pillGlobal.height,
                r: pill.morphRadius })
        }
        Component.onCompleted: publishPill()
        Connections {
            target: toplevel
            function onPillGlobalChanged() { toplevel.publishPill() }
        }
        Connections {
            target: pill
            function onMorphRadiusChanged() { toplevel.publishPill() }
        }

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
            // problem. "controlcenter" joins for the same reason — 440px tall.
            readonly property bool tallMode: mode === "launcher" || mode === "theme" || mode === "notif" || mode === "power" || mode === "controlcenter" || mode === "wallpaper" || mode === "clock" || mode === "clipboard" || mode === "polkit" || mode === "media" || mode === "updates" || mode === "recording"
            readonly property real morphRadius: tallMode ? 18 : height / 2
            bottomLeftRadius: morphRadius
	    bottomRightRadius: morphRadius
            // color:"#282828"
            // panel = same colour, alpha from appearance.transparency —
            // this rectangle is the surface for EVERY pill mode, so it
            // is the one that must let the wallpaper through
            color: Services.Colors.panel

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
                } else if (event.key === Qt.Key_Escape && Services.ClockCard.open) {
                    Services.ClockCard.close()
                    event.accepted = true
                } else if (event.key === Qt.Key_Escape && Services.ControlCenter.open) {
                    // plain in-pill CC — the advanced popup has its own
                    // handler in ControlCenterAdvanced.qml (different
                    // window, its keys never reach this one)
                    Services.ControlCenter.close()
                    event.accepted = true
                } else if (event.key === Qt.Key_Escape && Services.Media.open) {
                    // in-pill media card — same recipe as the clock card
                    Services.Media.close()
                    event.accepted = true
                } else if (event.key === Qt.Key_Escape && Services.ScreenRecording.open) {
                    // in-pill recording card — same recipe as the media card
                    Services.ScreenRecording.close()
                    event.accepted = true
                } else if (event.key === Qt.Key_Escape && Services.Updates.open) {
                    // in-pill updates card — same recipe as the media card
                    Services.Updates.close()
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

            // tray.hidden in settings.json — an array of StatusNotifier ids
            // (`qs ipc call tray ids` prints the ones currently registered,
            // `qs ipc call settings set tray.hidden '["id1","id2"]'` hides
            // them). Listed icons never render: not in the popup row, not
            // in its width, and the row reads empty if every icon is hidden.
            readonly property var trayHidden: {
                const v = Services.Settings.values["tray.hidden"]
                return Array.isArray(v)
                    ? v.map(x => String(x).trim().toLowerCase()) : []
            }
            readonly property var trayItems: SystemTray.items.values
                .filter(it => !trayHidden.includes(String(it.id).trim().toLowerCase()))

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
            // +22 for the category chip row, but only when the theme's
            // backgrounds folder actually HAS subfolders to chip — flat
            // dirs keep the old height to the pixel.
            function wallpaperStripHeight() {
                return Services.Themes.geom.listH
                    + (Services.Wallpapers.categories.length > 0 ? 22 : 0)
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
            // Polkit leads: an auth request is modal and preempts everything
            // (it also closes the keyboard-grab panels itself — see the
            // Services.Polkit Connections near the launcher's).
            readonly property string mode: toplevel.ownsOverlay(Services.Polkit) ? "polkit"
                : toplevel.ownsOverlay(Services.Launcher) ? "launcher"
                : toplevel.ownsOverlay(Services.Themes) ? "theme"
                : toplevel.ownsOverlay(Services.Wallpapers) ? "wallpaper"
                : toplevel.ownsOverlay(Services.ControlCenter) ? "controlcenter"
                : toplevel.ownsOverlay(Services.ClockCard) ? "clock"
                : toplevel.ownsOverlay(Services.Clipboard) ? "clipboard"
                : toplevel.ownsOverlay(Services.Media) ? "media"
                : toplevel.ownsOverlay(Services.ScreenRecording) ? "recording"
                : toplevel.ownsOverlay(Services.Updates) ? "updates"
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
                // auth prompt: 400 wide like the old dialog card, height
                // follows the content column (+20px margins top/bottom) —
                // same live-content-size trick as "notif"
                polkit:       () => Qt.size(400, polkitCol.implicitHeight + 40),
                launcher:     () => Qt.size(360, 12 + 30 + 8 + pill.confirmOverlayHeight() + 12),
                theme:        () => Qt.size(Services.Themes.geom.pillW, 24 + pill.themeGridHeight()),
                wallpaper:    () => Qt.size(Services.Themes.geom.pillW, 24 + pill.wallpaperStripHeight()),
                controlcenter:() => Qt.size(760, 440),
                clock:        () => Qt.size(620, 520),
                osd:          () => Qt.size(220, 35),
                notif:        () => Qt.size(420, Math.max(35, notificationContent.implicitHeight + 22)),
                power:        () => Qt.size(pill.powerRowWidth(), 24 + 64),
                clipboard:    () => Qt.size(430, 12 + 30 + 8 + clipboardContent.listH + 12),
                media:        () => Qt.size(528, 240),
                // cards are 260x300 / 280x380; pill = card + 24px each
                // side + 20px top/bottom (the media card's margins)
                recording:    () => Qt.size(308, 340),
                updates:      () => Qt.size(328, 420)
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

            // same shape as showOsd()/osdTimer above — morph in, hold, morph
            // back. notifT0 anchors the hover bank (see the MouseArea below).
            function showNotification(notification) {
                pill.currentNotification = notification
                pill.notifVisible = true
                notifTimer.interval = 4000
                pill.notifT0 = Date.now()
                notifTimer.restart()
            }

            property real notifT0: Date.now()

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
                // the pill's copy is about to be freed — null it (and
                // morph back) before quickshell deletes the object, or
                // the click handler below would invoke a dead
                // notification and segfault the shell
                function onNotificationClosed(notification) {
                    if (pill.currentNotification !== notification) return
                    pill.currentNotification = null
                    pill.notifVisible = false
                    notifTimer.stop()
                }
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

            // Polkit: focus the password field the moment a request lands —
            // the bar surface is keyboard-Exclusive while
            // Services.Polkit.open (toplevel predicate), so this is exactly
            // the launcher recipe that already types every day.
            //
            // The request must also CLEAR panels whose focus grabs would
            // starve the field: a HyprlandFocusGrab confines keyboard to
            // its own surface list, so an open control center (advanced
            // popup) or settings window would swallow every
            // keystroke meant for this prompt. The old full-screen dialog
            // never needed this — its scrim covered the whole screen.
            Connections {
                target: Services.Polkit
                function onOpenChanged() {
                    if (Services.Polkit.open) {
                        if (Services.ControlCenter.open) Services.ControlCenter.close()
                        if (Services.SettingsApp.open) Services.SettingsApp.hide()
                        if (Services.Updates.open) Services.Updates.close()
                        // only the owning bar's field may take focus —
                        // a second display means a second field
                        if (toplevel.ownsOverlay(Services.Polkit)) {
                            polkitField.text = ""
                            Qt.callLater(() => polkitField.forceActiveFocus())
                        }
                    } else {
                        polkitField.text = ""
                    }
                }
            }

            // Clock: type-the-task-the-moment-it-opens, exactly like the
            // launcher's search field — the bar is Exclusive while
            // ClockCard.open, so focus lands on taskInput and keys flow.
            // Only the owning bar focuses (second display = second card).
            Connections {
                target: Services.ClockCard
                function onOpenChanged() {
                    if (Services.ClockCard.open) {
                        if (toplevel.ownsOverlay(Services.ClockCard))
                            Qt.callLater(() => clockCardView.focusTaskInput())
                    } else {
                        clockCardView.clearTaskInput()
                    }
                }
            }

            // The media card has no text field, but the pill's Keys
            // handler still needs an activeFocusItem to receive Escape —
            // same reason the CC open path forces focus onto the pill.
            Connections {
                target: Services.Media
                function onOpenChanged() {
                    if (Services.Media.open && toplevel.ownsOverlay(Services.Media))
                        Qt.callLater(() => pill.forceActiveFocus())
                }
            }

            // Same as media: no text field, but the pill needs an
            // activeFocusItem so its Keys handler receives Escape.
            Connections {
                target: Services.ScreenRecording
                function onOpenChanged() {
                    if (Services.ScreenRecording.open && toplevel.ownsOverlay(Services.ScreenRecording))
                        Qt.callLater(() => pill.forceActiveFocus())
                }
            }

            Connections {
                target: Services.Updates
                function onOpenChanged() {
                    if (Services.Updates.open && toplevel.ownsOverlay(Services.Updates))
                        Qt.callLater(() => pill.forceActiveFocus())
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

                    MediaVisualiser {}

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
                // the segmented-pill identity — recording/updates live out in
                // the activity chips that slide from the pill's right edge;
                // media moved back INSIDE as MediaVisualiser (its chip +
                // detached popup are gone).
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

                        MediaVisualiser {}

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
            // e.g. "Screenshot taken" → opens the shot in tensaku;
            // right-click dismisses it now instead of waiting out
            // notifTimer. Hovering banks the 4s clock the same way the
            // popup card does — leave and it resumes with time left.
            // Sibling overlay on notificationContent, disabled whenever
            // the pill has morphed back so it can't eat clicks in other
            // pill modes.
            MouseArea {
                anchors.fill: notificationContent
                enabled: pill.mode === "notif"
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: {
                    if (notifTimer.running)
                        notifTimer.interval = Math.max(500, notifTimer.interval - (Date.now() - pill.notifT0))
                    notifTimer.stop()
                }
                onExited: {
                    pill.notifT0 = Date.now()
                    notifTimer.restart()
                }
                onClicked: (mouse) => {
                    if (mouse.button === Qt.RightButton) {
                        Services.Notifications.dismissNotification(pill.currentNotification)
                        pill.notifVisible = false   // morph back immediately
                    } else {
                        Services.Notifications.invokeDefault(pill.currentNotification)
                    }
                }
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

                        // placeholder: TextInput has no placeholderText of
                        // its own, so it's a zero-hit child painted over the
                        // text origin — clicks fall through to the input.
                        // Spells out the query languages: plain text is
                        // apps only, ">" switches to the settings catalog,
                        // ":" to the emoji list, and a math expression gets
                        // an answer row on top. width+elide so the hint
                        // truncates instead of running under the clip.
                        Text {
                            font.family: Services.Fonts.family
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            width: searchField.width
                            elide: Text.ElideRight
                            visible: searchField.text === ""
                            text: "apps — \">\" settings — \":\" emoji — math"
                            color: Services.Colors.text
                            opacity: 0.45
                            font.pixelSize: 14
                        }

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
                    // each prefix has exactly one haystack — name the one
                    // that was actually searched
                    text: Services.Launcher.query.trim().startsWith(">")
                        ? "No settings match"
                        : Services.Launcher.query.trim().startsWith(":")
                        ? "No emoji match"
                        : "No apps match"
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
                                visible: !modelData.glyph
                                source: modelData.icon !== "" ? Quickshell.iconPath(modelData.icon, true) : ""
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            // ":" emoji rows carry the character itself —
                            // painted in the color emoji font, since no
                            // theme icon exists for it
                            Text {
                                visible: !!modelData.glyph
                                anchors.verticalCenter: parent.verticalCenter
                                font.family: "Noto Color Emoji"
                                font.pixelSize: 20
                                text: modelData.glyph || ""
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
            // already a self-contained 760x440 component (draws its own
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
                    id: clockCardView
                    anchors.centerIn: parent
                }
            }

            // Media card folded in the same way — clicking the visualiser
            // in the rest row morphs the pill to 528x240 (modes.media) and
            // this card centers inside. Replaces the old detached popup
            // window + the activity chip it hung off: one surface, no
            // anchor math, drawn in the bar's own layer like the clock.
            // Header, progress rail (click/drag to seek), transport — the
            // rail's position ticks come from Media.qml's Timer, which only
            // runs while this card is open so the closed bar never pays
            // for a 1s heartbeat.
            Item {
                anchors.fill: parent
                opacity: pill.mode === "media" ? 1 : 0
                visible: (pill.mode === "media") || opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                Rectangle {
                    id: mediaCard
                    width: 480
                    height: 200
                    anchors.centerIn: parent
                    color: Services.Colors.surface
                    radius: 16
                    // same elevated-card language as the popup it replaces:
                    // tonal surface + hairline outline, one system with the
                    // tray/CC popups
                    border.width: 1
                    border.color: Services.Colors.low

                    Column {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 16

                        // header — art thumb, title/artist, app icon
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

                                    // real themed icon when the theme has
                                    // one (cliamp ships one; resolves from
                                    // local disk the frame the player
                                    // registers), nerd glyph otherwise
                                    Item {
                                        id: appGlyph
                                        width: 16
                                        height: 16
                                        anchors.verticalCenter: parent.verticalCenter

                                        Image {
                                            id: appIconImg
                                            anchors.fill: parent
                                            source: Services.Media.appIconSource
                                            visible: source.toString() !== ""
                                            fillMode: Image.PreserveAspectFit
                                            smooth: true
                                            asynchronous: true
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            visible: !appIconImg.visible
                                            font.family: Services.Fonts.family
                                            text: Services.Media.appIcon
                                            color: Services.Colors.accent
                                            font.pixelSize: 14
                                        }
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

                        // progress — elapsed · seekable rail · duration.
                        // Click/drag seeks (Media.seek guards on canSeek
                        // and length, so live radio stays inert); players
                        // that report no length get a flat muted rail with
                        // a LIVE tag instead of a fill. Position advances
                        // via the open-gated 1s Timer in services/Media.qml
                        // — the closed bar never ticks.
                        Row {
                            id: progressRow
                            width: parent.width
                            height: 16
                            spacing: 10

                            readonly property real frac: {
                                if (Services.Media.length <= 0) return 0
                                return Math.max(0, Math.min(1, Services.Media.position / Services.Media.length))
                            }

                            Text {
                                id: progressElapsed
                                width: 36
                                height: parent.height
                                verticalAlignment: Text.AlignVCenter
                                font.family: Services.Fonts.family
                                font.pixelSize: 11
                                color: Services.Colors.textMuted
                                text: Services.Media.position > 0
                                    ? Services.Media.formatTime(Services.Media.position) : ""
                            }

                            Item {
                                id: rail
                                height: parent.height
                                width: parent.width - progressElapsed.width - progressTotal.width - (progressRow.spacing * 2)

                                Rectangle {
                                    id: railTrack
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 5
                                    radius: 2.5
                                    color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                                   Services.Colors.text.b, 0.15)
                                }

                                Rectangle {
                                    anchors.left: railTrack.left
                                    anchors.verticalCenter: railTrack.verticalCenter
                                    width: railTrack.width * progressRow.frac
                                    height: 5
                                    radius: 2.5
                                    color: Services.Colors.accent
                                    visible: Services.Media.length > 0
                                }

                                // thumb rides the fill end, clamped inside
                                // the track so it never pokes past either edge
                                Rectangle {
                                    width: 9
                                    height: 9
                                    radius: 4.5
                                    color: Services.Colors.text
                                    visible: Services.Media.length > 0
                                    x: (railTrack.width - width) * progressRow.frac
                                    anchors.verticalCenter: railTrack.verticalCenter
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor

                                    function fracAt(mx) {
                                        return Math.max(0, Math.min(1, mx / width))
                                    }
                                    onPressed: (mouse) => Services.Media.seek(fracAt(mouse.x))
                                    onPositionChanged: (mouse) => {
                                        if (mouse.buttons & Qt.LeftButton)
                                            Services.Media.seek(fracAt(mouse.x))
                                    }
                                }
                            }

                            Text {
                                id: progressTotal
                                width: 36
                                height: parent.height
                                horizontalAlignment: Text.AlignRight
                                verticalAlignment: Text.AlignVCenter
                                font.family: Services.Fonts.family
                                font.pixelSize: 11
                                color: Services.Colors.textMuted
                                text: Services.Media.length > 0
                                    ? Services.Media.formatTime(Services.Media.length) : "LIVE"
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
                                    // nf-fa-backward U+F04A — plain back arrow,
                                    // replaces the old wrong codepoint
                                    text: "\uf04a"
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
                                    // nf-fa-pause F04C / nf-fa-play F04B
                                    text: Services.Media.playing ? "\uf04c" : "\uf04b"
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
                                    // nf-fa-forward U+F04E — plain forward arrow
                                    text: "\uf04e"
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
            }

            // Updates card folded the same way — the rest-row chip (or
            // `qs ipc call updates toggle`) morphs the pill to 328x420
            // (modes.updates) and the list centers inside. Replaces the
            // detached popup window + its FocusGrab: click-away is
            // the outsideCatcher (panelOpen), Esc the pill's Keys handler.
            Item {
                anchors.fill: parent
                opacity: pill.mode === "updates" ? 1 : 0
                visible: (pill.mode === "updates") || opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                UpdatesPopup {
                    anchors.centerIn: parent
                }
            }

            // Recording card folded the same way — the rec chip or the
            // control center's record tile morphs the pill to 308x340
            // (modes.recording) and the timer/stop card centers inside.
            // Replaces the detached popup window + its FocusGrab.
            Item {
                anchors.fill: parent
                opacity: pill.mode === "recording" ? 1 : 0
                visible: (pill.mode === "recording") || opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                ScreenRecordingPopup {
                    anchors.centerIn: parent
                }
            }

            // Polkit auth prompt — merged into the bar like the launcher
            // (was its own full-screen PanelWindow + scrim; see the
            // deprecated PolkitDialog.qml). The pill morphs to the prompt's
            // size (modes.polkit → 400 wide, height follows the column),
            // keyboard comes from the toplevel keyboardFocus predicate
            // (Services.Polkit.open → Exclusive, the launcher recipe), and
            // the pill mask gives the whole card input for free.
            //
            // Deliberately NOT in dismissPanels(): an auth request is
            // refused explicitly (Esc / Cancel), never by clicking away —
            // the outside catcher just swallows the click instead (the old
            // scrim's job, now panelOpen + the full-size mask region).
            Item {
                id: polkitContent
                anchors.fill: parent
                opacity: pill.mode === "polkit" ? 1 : 0
                visible: (pill.mode === "polkit") || opacity > 0.01
                Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                // color aliases — were `win.*` on the old dialog window
                readonly property color bg: Services.Colors.background
                readonly property color fg: Services.Colors.text
                readonly property color dim: Services.Colors.textMuted
                readonly property color accent: Services.Colors.accent
                readonly property color critical: Services.Colors.critical
                readonly property var flow: Services.Polkit.flow

                // absorbs clicks (no dismissal) and re-focuses the field so
                // a stray click never leaves the prompt typed into nowhere —
                // the old dialog's scrim MouseArea, in-pill form
                MouseArea {
                    anchors.fill: parent
                    onClicked: polkitField.forceActiveFocus()
                }

                // Esc cancels even when focus sits outside the field (keys
                // bubble from the focused item up the parent chain; the field
                // marks Escape accepted too, so the two never fight)
                Keys.onPressed: (event) => {
                    if (event.key === Qt.Key_Escape) {
                        Services.Polkit.cancel()
                        event.accepted = true
                    }
                }

                Column {
                    id: polkitCol
                    // plain x/y instead of anchors so the wrong-password
                    // shake can move the column (anchored items can't be
                    // offset on x)
                    x: 20 + shakeOffset
                    y: 20
                    width: parent.width - 40
                    spacing: 10

                    property real shakeOffset: 0

                    // ── header: lock + title + machine-readable action ──
                    Row {
                        width: parent.width
                        spacing: 12

                        Rectangle {
                            width: 40
                            height: 40
                            radius: 20
                            color: Services.Polkit.errorFlash ? polkitContent.critical : polkitContent.accent

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
                                color: polkitContent.bg
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
                                color: polkitContent.fg
                                text: "Authentication required"
                                elide: Text.ElideRight
                            }
                            Text {
                                width: parent.width
                                visible: polkitContent.flow && polkitContent.flow.actionId !== ""
                                font.family: Services.Fonts.family
                                font.pixelSize: 11
                                color: polkitContent.dim
                                text: polkitContent.flow ? polkitContent.flow.actionId : ""
                                elide: Text.ElideRight
                            }
                        }
                    }

                    // ── what polkitd wants done ──
                    Text {
                        width: parent.width
                        visible: polkitContent.flow && polkitContent.flow.message !== ""
                        wrapMode: Text.WordWrap
                        font.family: Services.Fonts.family
                        font.pixelSize: 12
                        color: polkitContent.dim
                        text: polkitContent.flow ? polkitContent.flow.message : ""
                    }

                    Rectangle { width: parent.width; height: 1; color: Services.Colors.low }

                    // ── account chips, only when the flow offers a choice ──
                    Row {
                        width: parent.width
                        spacing: 6
                        visible: polkitContent.flow && polkitContent.flow.identities.length > 1

                        Text {
                            font.family: Services.Fonts.family
                            font.pixelSize: 11
                            font.bold: true
                            color: polkitContent.dim
                            text: "Account"
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Repeater {
                            model: polkitContent.flow ? polkitContent.flow.identities : []

                            Rectangle {
                                id: chip
                                required property var modelData
                                readonly property bool selected:
                                    polkitContent.flow && polkitContent.flow.selectedIdentity === modelData

                                width: chipLabel.width + 18
                                height: 24
                                radius: 12
                                color: selected ? polkitContent.accent : Services.Colors.surface

                                Text {
                                    id: chipLabel
                                    anchors.centerIn: parent
                                    font.family: Services.Fonts.family
                                    font.pixelSize: 11
                                    font.bold: chip.selected
                                    color: chip.selected ? polkitContent.bg : polkitContent.dim
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
                        border.width: polkitField.activeFocus ? 1 : 0
                        border.color: polkitContent.accent

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
                            color: Services.Polkit.errorFlash ? polkitContent.critical : polkitContent.dim
                            opacity: polkitField.text === "" ? 1 : 0
                            text: Services.Polkit.submitted ? "Checking…"
                                : Services.Polkit.errorFlash ? "Wrong password"
                                : (polkitContent.flow && polkitContent.flow.inputPrompt !== "") ? polkitContent.flow.inputPrompt
                                : "Password"

                            Behavior on opacity {
                                NumberAnimation { duration: Services.Motion.effectsFast }
                            }
                        }

                        // focus MouseArea UNDER the input (declared first) so
                        // clicks in the side margins still focus the field
                        // while clicks on the text itself place the cursor
                        MouseArea {
                            anchors.fill: parent
                            onClicked: polkitField.forceActiveFocus()
                        }

                        TextInput {
                            id: polkitField
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            verticalAlignment: TextInput.AlignVCenter
                            clip: true
                            selectByMouse: true
                            font.family: Services.Fonts.family
                            font.pixelSize: 13
                            color: Services.Polkit.errorFlash ? polkitContent.critical : polkitContent.fg
                            selectionColor: polkitContent.accent
                            echoMode: (polkitContent.flow && polkitContent.flow.responseVisible)
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
                    }

                    // ── supplementary note / error line ──
                    Text {
                        width: parent.width
                        visible: polkitContent.flow && polkitContent.flow.supplementaryMessage !== ""
                                 && !Services.Polkit.submitted
                        wrapMode: Text.WordWrap
                        font.family: Services.Fonts.family
                        font.pixelSize: 11
                        color: (polkitContent.flow && polkitContent.flow.supplementaryIsError)
                               || Services.Polkit.errorFlash ? polkitContent.critical : polkitContent.dim
                        text: polkitContent.flow ? polkitContent.flow.supplementaryMessage : ""
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
                            color: polkitContent.accent
                            opacity: Services.Polkit.submitted ? 0.6 : 1

                            Text {
                                id: authTxt
                                anchors.centerIn: parent
                                font.family: Services.Fonts.family
                                font.pixelSize: 12
                                font.bold: true
                                color: polkitContent.bg
                                text: "Authenticate"
                            }

                            MouseArea {
                                anchors.fill: parent
                                enabled: !Services.Polkit.submitted
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    Services.Polkit.submit(polkitField.text)
                                    polkitField.text = ""
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
                                color: polkitContent.fg
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

                // wrong-password shake (omarchy's shakeOffset pattern) —
                // targets the column, since the anchored content root can't
                // slide on x
                SequentialAnimation {
                    id: shake
                    NumberAnimation { target: polkitCol; property: "shakeOffset"; to: -8; duration: 35; easing.type: Easing.OutQuad }
                    NumberAnimation { target: polkitCol; property: "shakeOffset"; to: 8; duration: 50; easing.type: Easing.InOutQuad }
                    NumberAnimation { target: polkitCol; property: "shakeOffset"; to: 0; duration: 55; easing.type: Easing.OutQuad }
                }
                Connections {
                    target: Services.Polkit
                    function onFailuresChanged() {
                        if (Services.Polkit.failures > 0) {
                            polkitField.text = ""   // never keep the wrong password around
                            shake.restart()
                        }
                    }
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

        // same trick for the tray popup — the whole feature is hover-driven,
        // so this is the only way to exercise it without a pointer:
        //   qs ipc call tray open / close / isOpen / count / ids
        IpcHandler {
            target: "tray"
            function open(): void { pill.trayTouch() }
            function close(): void { pill.trayOpen = false }
            function isOpen(): bool { return pill.trayOpen }
            // VISIBLE count — honours the tray.hidden list (raw registry
            // size lives in ids().length)
            function count(): int { return pill.trayItems.length }
            // every tray id currently registered — discovery aid for
            // building the tray.hidden list
            function ids(): string {
                return JSON.stringify(SystemTray.items.values.map(it => it.id))
            }
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
            // arithmetic the drop-downs did. Clamped both ways because a
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

            // same animate-then-hide window pattern the drop-down popups
            // used: show instantly on open, let the card spring, and wait
            // out the exit before the surface goes away
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
                    // hidden-by-config icons don't count — the popup says
                    // "No tray apps" when tray.hidden buries all of them
                    visible: pill.trayItems.length === 0
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
                    // centre-anchored, so if both showed they'd overlap.
                    // Both sides count pill.trayItems (raw list minus the
                    // tray.hidden ids), never the raw registry.
                    visible: pill.trayItems.length > 0
                    spacing: 2

                    Repeater {
                        model: pill.trayItems

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
            // is different: the pill itself IS the 440px-tall panel now, so
            // "below it" meant "below the entire panel", landing at the
            // bottom instead of running alongside it.
            anchor.rect.y: pill.y
            implicitWidth: 260
            // matches ControlCenterAdvanced's own 380px card, NOT the
            // pill's 440 — the window follows the CONTENT (advSizer is
            // centerIn + content-sized), so matching the pill would just
            // add transparent bands that eat desktop clicks beside it
            implicitHeight: 380
            color: "transparent"

            property bool windowVisible: false
            visible: windowVisible

            // Same as settingsPopup (below): give the popup's content Qt
            // active focus the moment it maps, so an input inside (the wifi
            // password row) isn't fighting the bar surface for it.
            onVisibleChanged: if (visible) advPanel.forceActiveFocus()

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

        // Updates + recording no longer have PopupWindows — they morph
        // inside the pill (modes "updates" / "recording"), same recipe as
        // media and the clock card: the pill mask + outsideCatcher do
        // click-away, Esc goes through the pill's Keys handler, and the
        // toplevel keyboardFocus predicate delivers keys.

        // Clock card: NO HyprlandFocusGrab. A grab and the Exclusive
        // keyboardFocus predicate entry on the SAME surface fight in
        // Hyprland — the grab installs a seat grab, the predicate's
        // exclusive-keyboard commit displaces it, the seat grab's
        // callback finishes the focus grab with sendCleared=true, and
        // quickshell's onCleared closed the popup 76ms after opening
        // (reproducible: open → cleared → closed, every time). Power/
        // CC survive only because they are NOT in the predicate. The
        // clock follows the launcher recipe instead: predicate delivers
        // keyboard (it types every day), the full-surface mask +
        // outsideCatcher handle click-away, Esc closes via the pill's
        // Keys handler above.

        HyprlandFocusGrab {
            id: ccGrab
            // Timestamp of the last advancedPanel change — onCleared uses
            // it to tell the two clear flavors apart (see below).
            property real flipAt: 0
            // toplevel instead of the old controlCenterPopup — the panel
            // lives inside the pill (inside toplevel) now. Same pattern as
            // the PowerMenu grab below, which faced this exact change earlier.
            //
            // While the ADVANCED popup is up it must be the ONLY whitelisted
            // surface: with toplevel also in the set the compositor keeps
            // keyboard on the bar layer surface (it never redirects focus
            // just because a new popup maps), so the popup's password field
            // received zero keystrokes. The settings popup types fine
            // because ITS grab whitelists only that popup — same rule here.
            // Closed → back to [toplevel] for the in-pill CC panel.
            windows: Services.ControlCenter.advancedPanel !== ""
                ? [controlCenterAdvancedPopup]
                : [toplevel]

            // `active` is driven imperatively, NOT by a declarative binding.
            // quickshell writes active=false itself on every clear
            // (onGrabCleared → setActive(false)), and the window-list flip
            // above reliably produces one transient clear: the toplevel
            // leaves the grab before the popup's surface is committed, so
            // for a frame the grab is empty. That write destroys a
            // declarative binding (its dependencies never change again, so
            // it cannot re-evaluate) — the grab would stay dead while the
            // panel is open and keyboard would never be confined to the
            // popup. Every transition therefore re-arms explicitly: the
            // destroy + recreate below also gives a FRESH activation, which
            // is what makes the compositor move keyboard focus into the
            // popup — settings gets its focus that same way on every open.
            //
            // onCleared must therefore DISTINGUISH clear flavors: the
            // transient one lands within a frame or two of advancedPanel
            // flipping (re-arm — the popup needs the grab to keep typing),
            // while any later clear is the seat grab's dismissal signal —
            // the user clicked or focused away, the exact mechanism the
            // power menu closes on — so close everything. Before this
            // timing guard, EVERY clear during the popup was re-armed and
            // click-away silently did nothing.
            onCleared: {
                if (Services.ControlCenter.advancedPanel !== ""
                    && Date.now() - ccGrab.flipAt < 250)
                    // transient clear mid-flip — re-arm once settled
                    Qt.callLater(function() {
                        if (toplevel.ownsOverlay(Services.ControlCenter))
                            ccGrab.active = true
                    })
                else
                    Services.ControlCenter.close()
            }
        }

        // Drives the grab above imperatively — a sibling, because
        // HyprlandFocusGrab is a C++ type with no default property, so a
        // declared child object is a load error ("Cannot assign to
        // non-existent default property").
        Connections {
            target: Services.ControlCenter
            function updateGrab() {
                ccGrab.active = toplevel.ownsOverlay(Services.ControlCenter)
            }
            // the service's own onOpenChanged writes ownerScreen before
            // these run (it connected at singleton creation), but the
            // ownerScreen hook keeps the check honest either way
            function onOpenChanged() {
                updateGrab()
                // Give the pill Qt active focus while the panel is up, so
                // the pill's Keys.onPressed actually receives Escape —
                // without an activeFocusItem inside the pill, key events
                // land on the window root and bubble past it. The popup
                // window focuses advPanel itself (onVisibleChanged there).
                if (Services.ControlCenter.open && toplevel.ownsOverlay(Services.ControlCenter))
                    Qt.callLater(() => pill.forceActiveFocus())
            }
            function onOwnerScreenChanged() { updateGrab() }
            function onAdvancedPanelChanged() {
                ccGrab.flipAt = Date.now()
                if (!toplevel.ownsOverlay(Services.ControlCenter)) return
                // let the grab's `windows` binding settle first, then
                // destroy + recreate over the new list
                Qt.callLater(function() {
                    if (!toplevel.ownsOverlay(Services.ControlCenter)) return
                    ccGrab.active = false
                    ccGrab.active = true
                })
            }
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
