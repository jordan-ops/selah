import QtQuick
import Quickshell
import Quickshell.Io
import QtQuick.Controls   // ToolTip attached property only — no Controls instances
import "./services" as Services

// The settings app window's content: sidebar pages + rows rendered by
// type. It draws and routes only — every value it shows or writes lives
// in services/ (Settings, Themes, …) or goes out through qs ipc exactly
// like the hypr binds do. Which settings exist is not this file's
// business: services/SettingsCatalog.qml is the one list, and the
// launcher indexes that same list (omasettings' one-source rule).
FocusScope {
    id: app
    width: Services.SettingsApp.winW
    height: Services.SettingsApp.winH
    focus: true

    readonly property string currentPage: Services.SettingsApp.page
    readonly property var pageEntries: app.currentPage === "about"
        ? app.ffRows
        : Services.SettingsCatalog.entries.filter(e => e.page === app.currentPage)

    // sidebar order — drives the page-switch slide direction: moving down
    // the sidebar = forward = the new page enters from the right (M3
    // shared-axis X), moving up = enters from the left.
    readonly property int pageIdx: Math.max(0, Services.SettingsCatalog.pages
        .findIndex(p => p.id === app.currentPage))
    property int prevPageIdx: 0
    property int pageDir: 1

    // ——— keyboard navigation ——— navIdx rings through the sidebar page
    // list (wrapping); the ring only shows after the first arrow press
    // so pure-mouse sessions never see it, and the same arrows drive
    // the search result list while a query is live.
    property int navIdx: 0
    property bool navEngaged: false
    property int searchSel: 0

    // ——— per-page filter (long pages: Widgets has 60 rows) ——— the
    // text field mirrors the CURRENT page's filter; the map remembers
    // each page's text while the window stays open and is emptied when
    // it hides. `visibleEntries` below is what rowsList renders.
    property var pageFilters: ({})
    readonly property bool showFilter:
        app.currentPage !== "about" && app.pageEntries.length > 15
    readonly property int filterMatches: {
        const all = app.visibleEntries
        let n = 0
        for (let i = 0; i < all.length; i++)
            if (all[i].type !== "section") n++
        return n
    }

    // case-insensitive label+description filter; sections survive only
    // while a row under them still matches, so headings never dangle
    readonly property var visibleEntries: {
        const all = app.pageEntries
        const q = filterInput.text.trim().toLowerCase()
        if (q === "") return all
        const out = []
        let held = []
        for (let i = 0; i < all.length; i++) {
            const e = all[i]
            if (e.type === "section") { held.push(e); continue }
            const hay = (String(e.label || "") + " "
                         + String(e.description || "")).toLowerCase()
            if (hay.indexOf(q) < 0) continue
            for (let j = 0; j < held.length; j++) out.push(held[j])
            held = []
            out.push(e)
        }
        return out
    }

    // every type the row renderer (and its Loader) knows — a catalog
    // typo logs a warning here AND in the Loader's default arm instead
    // of silently rendering the wrong control
    readonly property var knownTypes: ["section", "info", "action", "switch",
        "choice", "slider", "hyprswitch", "dropdown", "swatches", "wallpapers",
        "carousel", "buttons", "cmdswitch", "cmdslider", "appmixer", "voicecard", "powercard", "netcard",
        "timecard", "textsize", "keybinds", "xcompose", "animcard",
        "lockstyle", "netlist", "btlist"]

    // components that draw their own material card — they never share a
    // group-card container with plain rows and act as group breakers,
    // exactly like a section heading does (macOS inset-group parity)
    readonly property var ownCardTypes: ["powercard", "netcard", "timecard",
        "carousel", "appmixer", "voicecard", "keybinds", "xcompose", "animcard",
        "lockstyle", "netlist", "btlist"]
    function typeIsOwnCard(t) { return app.ownCardTypes.indexOf(t) >= 0 }

    // launcher deep-link: show() sets focusId BEFORE the sizer window has
    // grown, so positionViewAtIndex runs into a 0-height list and lands
    // the row off-screen (deep-linked cards ended up clipped behind the
    // footer). Resolve right away when the list already has height (jump
    // from search while open), then once more after the sizer + row-height
    // springs settle — rowsList re-arms the settle pass while it grows.
    property string pendingId: ""

    function resolveFocus() {
        app.pendingId = Services.SettingsApp.focusId || ""
        if (app.pendingId === "") return
        // a deep-linked row the per-page filter hides would position
        // against a stale index — drop the filter first, then settle
        if (app.visibleEntries.findIndex(e => e.id === app.pendingId) < 0
            && filterInput.text !== "")
            app.clearFilter()
        const i = app.visibleEntries.findIndex(e => e.id === app.pendingId)
        if (i >= 0 && rowsList.height > 100)
            rowsList.positionViewAtIndex(i, ListView.Contain)
        pendingIdle.restart()
    }

    Timer {
        id: pendingIdle
        interval: 400   // past both the sizer spring and the row-height spring
        onTriggered: {
            if (app.pendingId === "") return
            const i = app.visibleEntries.findIndex(e => e.id === app.pendingId)
            if (i >= 0 && rowsList.height > 100)
                rowsList.positionViewAtIndex(i, ListView.Contain)
            // deep-link finished: drop the accent border instead of
            // leaving it lit on that row for the rest of the session
            app.pendingId = ""
            Services.SettingsApp.focusId = ""
        }
    }

    // ——— sidebar reveal: pages past the visible slice (Login screen,
    // Default apps, Neovim, About) sit below the sidebar's bottom edge, so
    // the active highlight ended up off-screen after a deep-link. Slide the
    // flick just far enough to contain the active row — M3 standard set's
    // quick pair, same easing as the panel — and no-op when the row is
    // already visible, so every hook (page switch, settle, search clear)
    // is idempotent.
    function revealSidebarRow() { revealSidebarRowAt(app.pageIdx) }

    function revealSidebarRowAt(idx) {
        if (!sidebarFlick || sidebarFlick.height <= 10
            || sidebarFlick.contentHeight <= sidebarFlick.height) return
        const rowH = 36 + sidebarCol.spacing
        const rowTop = idx * rowH
        let to = sidebarFlick.contentY
        if (rowTop < sidebarFlick.contentY)
            to = rowTop                                    // above the fold
        else if (rowTop + 36 <= sidebarFlick.contentY + sidebarFlick.height)
            return                                         // fully visible
        else
            to = rowTop + 36 - sidebarFlick.height         // below the fold
        to = Math.max(0, Math.min(to,
            sidebarFlick.contentHeight - sidebarFlick.height))
        if (Math.abs(to - sidebarFlick.contentY) < 1) return
        sidebarReveal.from = sidebarFlick.contentY
        sidebarReveal.to = to
        sidebarReveal.restart()
    }

    NumberAnimation {
        id: sidebarReveal
        target: sidebarFlick
        property: "contentY"
        duration: Services.Motion.effectsFast
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Services.Motion.emphasizedDecelerate
    }

    onCurrentPageChanged: {
        revealSidebarRow()
        // keyboard ring follows the page; the per-page filter restores
        // whatever this page was left with (usually nothing)
        navIdx = pageIdx
        navEngaged = false
        filterInput.text = app.pageFilters[app.currentPage] || ""
    }

    // filters + toasts live only while the window does
    Connections {
        target: Services.SettingsApp
        function onOpenChanged() {
            if (!Services.SettingsApp.open) {
                SettingsToast.clear()
                app.pageFilters = ({})
                filterInput.text = ""
                navEngaged = false
                searchInput.text = ""
                return
            }
            // belt-and-braces: if the show() landed while the catalog
            // binding was still settling, the ring still starts on the
            // page you're actually viewing
            navIdx = pageIdx
            navEngaged = false
        }
    }

    // ——— About page: live fastfetch details, fed into the normal info
    // rows (label/value) instead of the old curated content. Cached after
    // the first run — fastfetch takes ~60ms and the page-swap dip covers
    // the brief fill-in.
    property var ffRows: []
    property bool ffDone: false   // one run finished (even a failed one)

    Process {
        id: ffProc
        // bash wrapper: spawned under qs, fastfetch would report the shell
        // as "qs" (it reads its direct parent); under bash it reports the
        // real one.
        command: ["bash", "-c", "fastfetch --logo none"]
        stdout: StdioCollector {
            onStreamFinished: {
                const rows = []
                const lines = text.split("\n")
                for (const raw of lines) {
                    const line = raw.trim()
                    const i = line.indexOf(": ")
                    if (i < 1) continue   // title, dashes, color blocks
                    // spawned under qs, fastfetch's shell detection walks
                    // up to quickshell itself — wrong answer, drop the row
                    if (line.indexOf("Shell: ") === 0) continue
                    rows.push({ id: "ff" + rows.length, page: "about",
                                type: "info", label: line.slice(0, i),
                                value: line.slice(i + 2) })
                }
                app.ffRows = rows
                console.log("FF parse: " + rows.length + " rows; labels=[" + rows.map(r => r.label).join("|") + "]")
            }
        }
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "")
                console.log("SettingsWindow: fastfetch stderr:", text.trim())
        }
        // empty output OR a failed run → the page shows an honest
        // message (below) instead of a silently blank card stack
        onExited: (exitCode) => {
            app.ffDone = true
            if (exitCode !== 0 || app.ffRows.length === 0)
                console.log("SettingsWindow: fastfetch produced nothing (exitCode "
                            + exitCode + ", " + app.ffRows.length + " rows)")
        }
    }

    Connections {
        target: Services.SettingsApp
        function onPageChanged() {
            if (Services.SettingsApp.page === "about" && app.ffRows.length === 0) {
                ffProc.running = false
                ffProc.running = true
            }
        }
    }

    // ——— sidebar search: matches pages by name and entries by label /
    // description / keywords AND every option's label/value across
    // every page; exact substring ranks ahead of fuzzy subsequence
    // ("gpa" → "gaps"), and picking a hit jumps via the existing page +
    // focusId deep-link (rowsList scrolls it into view and flashes it)
    //———
    // -1 = no match; 0 = substring; 1 = subsequence (+1 more when the
    // hit only came from an option's label/value)
    function matchRank(q, hay) {
        if (hay.indexOf(q) >= 0) return 0
        let j = 0
        for (let i = 0; i < hay.length && j < q.length; i++)
            if (hay.charAt(i) === q.charAt(j)) j++
        return j === q.length ? 1 : -1
    }

    readonly property var searchResults: {
        const q = searchInput.text.trim().toLowerCase()
        if (q === "") return []
        const out = []
        const pages = Services.SettingsCatalog.pages
        for (let i = 0; i < pages.length; i++) {
            const rank = app.matchRank(q, pages[i].name.toLowerCase())
            if (rank < 0) continue
            out.push({ kind: "page", rank: rank, title: pages[i].name,
                       caption: "Page", page: pages[i].id, fid: "" })
        }
        // searchable = entries minus section headings, so a page's own
        // group labels never show up as hits
        const all = Services.SettingsCatalog.searchable
        for (let i = 0; i < all.length; i++) {
            const e = all[i]
            if (!e.label) continue
            const hay = (e.label + " " + (e.description || "") + " "
                         + (e.keywords || "")).toLowerCase()
            let rank = app.matchRank(q, hay)
            if (rank < 0 && e.options) {
                // each option's label AND value is a fair search target —
                // query "scrolling" finds the layout row through its chip
                let ohay = ""
                for (let k = 0; k < e.options.length; k++)
                    ohay += " " + (e.options[k].label || "") + " "
                            + String(e.options[k].value !== undefined
                                     ? e.options[k].value : "")
                rank = app.matchRank(q, ohay.toLowerCase())
                if (rank >= 0) rank += 1   // option-only hits rank below
            }
            if (rank < 0) continue
            let pname = e.page
            for (let j = 0; j < pages.length; j++)
                if (pages[j].id === e.page) pname = pages[j].name
            // breadcrumb: "Page name › Label" under the title
            out.push({ kind: "entry", rank: rank, title: e.label,
                       caption: pname + " › " + e.label,
                       page: e.page, fid: e.id || "" })
        }
        // best hit first (substring before subsequence), capped like
        // before — stable sort keeps catalog order within a rank
        out.sort((a, b) => a.rank - b.rank)
        return out.slice(0, 14)
    }

    // the highlighted result follows the set (arrow keys drive it; the
    // first hit is the default so Enter always jumps somewhere)
    onSearchResultsChanged: searchSel = 0

    function jumpTo(r) {
        // a per-page filter must never swallow the jump target
        app.clearFilterFor(r.page)
        Services.SettingsApp.page = r.page
        if (r.kind === "entry" && r.fid) {
            // reset-then-set so the deep-link fires even when the target
            // row lives on the page we're already viewing
            Services.SettingsApp.focusId = ""
            Services.SettingsApp.focusId = r.fid
        }
        searchInput.text = ""
    }

    function clearFilterFor(pageId) {
        if (app.currentPage !== pageId) {
            if (app.pageFilters[pageId]) {
                const m = Object.assign({}, app.pageFilters)
                m[pageId] = ""
                app.pageFilters = m
            }
            return
        }
        if (filterInput.text !== "") filterInput.text = ""
    }

    function clearFilter() { clearFilterFor(app.currentPage) }

    function infoValue(e) {
        if (e.source === "theme")     return Services.Themes.currentTheme || "—"
        if (e.source === "wallpaper") return Services.Wallpapers.current || "—"
        if (e.source === "battery")   return Services.Battery.hasBattery
                                             ? Services.Battery.percent + "%" +
                                               (Services.Battery.charging ? " · charging" : "")
                                             : "No battery"
        if (e.source === "net")       return (Services.Network.isWifi ? "Wi-Fi" : "Wired") +
                                               (Services.Network.connected ? "" : " · offline")
        if (e.source === "pkgupdates") return Services.Updates.count > 0
                                             ? Services.Updates.count + " pending"
                                             : "Up to date"
        if (e.source === "repoupdate") return Services.Updates.repoStatusText
        return e.value || ""
    }

    function switchOn(e) {
        const v = Services.Settings.get(e.key, false)
        return v === true || v === "true"
    }

    function applyChoice(e, v) {
        if (e.source === "themes") Services.Themes.setSize(v)
        else Services.Settings.set(e.key, v)
    }

    function choiceValue(e) {
        if (e.source === "themes") return Services.Themes.size
        return Services.Settings.get(e.key, e.options ? e.options[0].value : "")
    }

    Process {
        id: actionRunner
        property string label: ""
        // quiet on success (exit 0, silent stderr); anything else is a
        // failure worth a toast — a missing binary lands in stderr AND
        // a nonzero exit on most systems, one toast each way
        stderr: StdioCollector {
            onStreamFinished: {
                const first = text.trim().split("\n")[0]
                if (first !== "")
                    SettingsToast.push("«" + actionRunner.label + "» — " + first, true)
            }
        }
        onExited: (exitCode) => {
            if (exitCode !== 0)
                SettingsToast.push("«" + actionRunner.label
                                   + "» failed — command not found?", true)
        }
    }
    function runCommand(e) {
        actionRunner.label = e && e.label ? String(e.label) : "Command"
        actionRunner.command = e && e.command ? e.command : []
        actionRunner.running = true
    }

    function moveNav(delta) {
        const n = Services.SettingsCatalog.pages.length
        if (n === 0) return
        navEngaged = true
        navIdx = (navIdx + delta + n) % n
        revealSidebarRowAt(navIdx)
    }

    // Enter with a live query → the highlighted hit; without one → the
    // highlighted page
    function activateNav() {
        if (searchInput.text.trim() !== "") {
            if (app.searchResults.length > 0)
                app.jumpTo(app.searchResults[Math.min(searchSel,
                                                      app.searchResults.length - 1)])
            return
        }
        const pages = Services.SettingsCatalog.pages
        if (navIdx >= 0 && navIdx < pages.length) {
            Services.SettingsApp.page = pages[navIdx].id
            navEngaged = false
        }
    }

    // Ctrl+K / Ctrl+F anywhere → search; Esc clears a live query first,
    // then closes; arrows drive the result list while searching and the
    // sidebar ring otherwise; Enter activates the highlighted item
    Keys.onPressed: (event) => {
        const k = event.key
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        if (ctrl && (k === Qt.Key_K || k === Qt.Key_F)) {
            searchInput.forceActiveFocus()
            searchInput.selectAll()
            event.accepted = true
            return
        }
        if (k === Qt.Key_Escape) {
            if (confirmDlg.open) { confirmDlg.cancel(); event.accepted = true; return }
            if (filterInput.activeFocus && filterInput.text !== "") {
                filterInput.text = ""
                event.accepted = true
                return
            }
            if (searchInput.text !== "") {
                searchInput.text = ""
                event.accepted = true
                return
            }
            Services.SettingsApp.hide()
            event.accepted = true
            return
        }
        const searching = searchInput.text.trim() !== ""
        const n = searching ? app.searchResults.length
                            : Services.SettingsCatalog.pages.length
        if (n === 0) return
        if (k === Qt.Key_Down || k === Qt.Key_Up) {
            const delta = k === Qt.Key_Down ? 1 : -1
            if (searching)
                searchSel = (searchSel + delta + n) % n
            else
                moveNav(delta)
            event.accepted = true
            return
        }
        if (k === Qt.Key_Return || k === Qt.Key_Enter) {
            activateNav()
            event.accepted = true
        }
    }

    // ——— Hyprland-matching window border ——— colors + width are the
    // compositor's own options (colors.lua rewrites them per theme, so a
    // re-read on palette change keeps the panel in step with the screen);
    // drawn as an angled gradient ring like hyprland's borders. Shape:
    // resting/disabled = the panel's current 16; while the window is
    // activated (shown + focused) it bounces to a rounder rectangle on a
    // slightly slower-than-pop spring so the bounce has time to read.
    readonly property bool activated: Services.SettingsApp.open && app.activeFocus
    property real shapeR: 16
    property var activeStops: ["ee81a1c1", "ee88c0d0"]
    property var inactiveStops: ["aa4c566a"]
    property real borderAngle: 45
    property real borderWidth: 2

    onActivatedChanged: {
        shapeR = app.activated ? 24 : 16
        if (app.activated) borderRd.running = true
    }

    Behavior on shapeR {
        // the requested "slightly slower" bounce — springier than pop,
        // damped enough to watch the corners settle
        SpringAnimation { spring: 13; damping: 0.52 }
    }

    // theme switches rewrite colors.lua → hyprland's border options —
    // re-read whenever the palette moves
    Connections {
        target: Services.Colors
        function onAccentChanged() { borderRd.running = true }
    }

    Process {
        id: borderRd
        command: ["bash", "-c",
            'hyprctl getoption general:col.active_border; echo ---; '
            + 'hyprctl getoption general:col.inactive_border; echo ---; '
            + 'hyprctl getoption general:border_size']
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = String(text).split("---")
                if (parts.length < 3) return
                const a = parts[0].match(/[0-9a-fA-F]{8}/g)
                const i = parts[1].match(/[0-9a-fA-F]{8}/g)
                const ang = parts[0].match(/(\d+)deg/)
                const wid = parts[2].match(/int:\s*(\d+)/)
                if (a && a.length) app.activeStops = a
                if (i && i.length) app.inactiveStops = i
                if (ang) app.borderAngle = parseInt(ang[1])
                if (wid) app.borderWidth = parseInt(wid[1])
            }
        }
    }

    // card
    Rectangle {
        id: panel
        anchors.fill: parent
        radius: app.shapeR
        // panel = background with the appearance.transparency alpha —
        // settings lets the wallpaper through, text inside keeps the
        // opaque background (880/942 below)
        color: Services.Colors.panel
        border.color: Services.Colors.surface
        border.width: 1

        // hyprland-style border ring — angled gradient stroke hugging the
        // panel corners at the live shape radius; stops/width/angle come
        // from hyprctl, active vs inactive stops from window activation
        Canvas {
            id: borderRing
            anchors.fill: parent

            function hexa(hex) {
                // hyprland stops arrive #AARRGGBB or bare AARRGGBB → rgba()
                const s = hex.charAt(0) === "#" ? hex.slice(1) : hex
                if (s.length !== 8)
                    return hex.charAt(0) === "#" ? hex : "#" + hex
                const a = parseInt(s.slice(0, 2), 16) / 255
                const r = parseInt(s.slice(2, 4), 16)
                const g = parseInt(s.slice(4, 6), 16)
                const b = parseInt(s.slice(6, 8), 16)
                return "rgba(" + r + ", " + g + ", " + b + ", "
                    + a.toFixed(3) + ")"
            }

            onPaint: {
                const ctx = getContext("2d")
                ctx.clearRect(0, 0, width, height)
                const w = width, h = height, bw = app.borderWidth, r = app.shapeR
                const stops = app.activated ? app.activeStops : app.inactiveStops
                if (bw < 1 || !stops || stops.length === 0) return
                // angled linear gradient across the panel diagonal
                const rad = app.borderAngle * Math.PI / 180
                const len = Math.sqrt(w * w + h * h) / 2
                const dx = Math.cos(rad) * len
                const dy = -Math.sin(rad) * len
                const g = ctx.createLinearGradient(w / 2 - dx, h / 2 - dy,
                                                   w / 2 + dx, h / 2 + dy)
                for (let i = 0; i < stops.length; i++)
                    g.addColorStop(stops.length > 1 ? i / (stops.length - 1) : 0,
                                   hexa(stops[i]))
                ctx.strokeStyle = g
                ctx.lineWidth = bw
                const m = bw / 2, rr = Math.max(0.01, r - m)
                ctx.beginPath()
                ctx.moveTo(m + rr, m)
                ctx.lineTo(w - m - rr, m)
                ctx.arcTo(w - m, m, w - m, m + rr, rr)
                ctx.lineTo(w - m, h - m - rr)
                ctx.arcTo(w - m, h - m, w - m - rr, h - m, rr)
                ctx.lineTo(m + rr, h - m)
                ctx.arcTo(m, h - m, m, h - m - rr, rr)
                ctx.lineTo(m, m + rr)
                ctx.arcTo(m, m, m + rr, m, rr)
                ctx.closePath()
                ctx.stroke()
            }

            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()

            Connections {
                target: app
                function onShapeRChanged() { borderRing.requestPaint() }
                function onActivatedChanged() { borderRing.requestPaint() }
                function onActiveStopsChanged() { borderRing.requestPaint() }
                function onInactiveStopsChanged() { borderRing.requestPaint() }
                function onBorderAngleChanged() { borderRing.requestPaint() }
                function onBorderWidthChanged() { borderRing.requestPaint() }
            }
        }

        // ——— sidebar backdrop ——— the macOS System Settings material:
        // a subtle surface strip behind the pages column with a hairline
        // against the content pane. Sits behind sidebarBox (declared
        // after it, so it paints first).
        Rectangle {
            id: sidebarBackdrop
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: 230
            color: Qt.rgba(Services.Colors.surface.r, Services.Colors.surface.g,
                           Services.Colors.surface.b, 0.45)

            Rectangle {
                anchors.right: parent.right
                width: 1
                height: parent.height
                color: Services.Colors.low
                opacity: 0.35
            }
        }

        // sidebar — pages straight from the catalog; wheel/drag scroll
        // when the page list outgrows the window. The search field on
        // top is the window's only query box (Ctrl+K focuses it).
        Item {
            id: sidebarBox
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            anchors.topMargin: 12
            anchors.bottomMargin: 8
            width: 230

            Rectangle {
                id: searchField
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                height: 32
                radius: 10
                color: Services.Colors.surface
                border.color: Services.Colors.low
                border.width: 1

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: searchInput.forceActiveFocus()
                }

                TextInput {
                    font.family: Services.Fonts.family
                    id: searchInput
                    anchors.left: parent.left
                    anchors.right: clearBtn.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 4
                    clip: true
                    color: Services.Colors.text
                    font.pixelSize: 12
                    selectionColor: Services.Colors.accent
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Search settings"
                    onAccepted: app.activateNav()

                    Text {
                        font.family: Services.Fonts.family
                        visible: searchInput.text === ""
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Search settings…"
                        color: Services.Colors.textMuted
                        font.pixelSize: 12
                    }
                }

                Rectangle {
                    id: clearBtn
                    visible: searchInput.text !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? 18 : 0
                    height: 18
                    radius: 9
                    color: clearMa.containsMouse ? Services.Colors.surfaceAlt : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: "Clear search"
                    ToolTip.visible: clearMa.containsMouse
                    ToolTip.delay: 400
                    ToolTip.text: "Clear search"
                    Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                    Text {
                        font.family: Services.Fonts.family
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 10
                        color: Services.Colors.textMuted
                    }

                    MouseArea {
                        id: clearMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            searchInput.text = ""
                            searchInput.forceActiveFocus()
                        }
                    }
                }
            }

            Flickable {
                id: sidebarFlick
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: searchField.bottom
                anchors.bottom: parent.bottom
                anchors.topMargin: 8
                contentWidth: width
                contentHeight: sidebarCol.implicitHeight + 6
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                // re-run the reveal when the sidebar gets its real height
                // (deep-link opens before the sizer spring settles) or when
                // clearing search repopulates the page list
                onHeightChanged: app.revealSidebarRow()
                onContentHeightChanged: app.revealSidebarRow()

                Column {
                    id: sidebarCol
                    width: sidebarFlick.width
                    spacing: 2

                    Repeater {
                        model: searchInput.text.trim() === ""
                               ? Services.SettingsCatalog.pages : []

                        delegate: Rectangle {
                            readonly property bool active: Services.SettingsApp.page === modelData.id
                            // keyboard ring — only lit once arrow keys
                            // have been used, so mouse sessions never
                            // see an extra outline on the current page
                            readonly property bool navSel:
                                app.navEngaged && index === app.navIdx
                            x: 10
                            width: sidebarCol.width - 20
                            height: 36
                            radius: 10
                            // macOS System Settings selection — the filled
                            // rounded pill; accentSurface floors the label
                            // contrast (kanagawa derives primary ==
                            // on_background, which would paint the name in
                            // the pill's own colour)
                            color: active ? Services.Colors.accentSurface : "transparent"
                            border.width: navSel ? 1 : 0
                            border.color: Services.Colors.accent
                            Accessible.role: Accessible.PageTab
                            Accessible.name: modelData.name

                            Behavior on color {
                                ColorAnimation {
                                    duration: Services.Motion.effectsFast
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                }
                            }
                            Behavior on border.width {
                                NumberAnimation {
                                    duration: Services.Motion.effects
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                }
                            }

                            Row {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 8

                                Text {
                                    font.family: Services.Fonts.family
                                    text: modelData.name
                                    font.pixelSize: 13
                                    font.bold: parent.parent.active
                                    color: parent.parent.active
                                        ? Services.Colors.text : Services.Colors.textMuted

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Services.Motion.effectsFast
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                        }
                                    }
                                }
                            }

                            // pending-changes dot — while Apply/Revert
                            // has something waiting on ANY page; sits on
                            // the accent pill when its page is active, so
                            // it rides the contrast-floored text colour
                            Rectangle {
                                anchors.right: parent.right
                                anchors.rightMargin: 12
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: Services.Colors.text
                                opacity: parent.active && Services.SettingsApp.dirty ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: Services.Motion.effectsFast
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: Services.SettingsApp.page = modelData.id
                            }
                        }
                    }

                    // search hits — label + page caption; picking one
                    // jumps and clears the query
                    Repeater {
                        model: searchInput.text.trim() === "" ? [] : app.searchResults

                        delegate: Rectangle {
                            readonly property bool selected: index === app.searchSel
                            x: 10
                            width: sidebarCol.width - 20
                            height: 40
                            radius: 10
                            color: resMa.containsMouse || selected
                                ? Services.Colors.surface : "transparent"
                            border.width: selected ? 1 : 0
                            border.color: Services.Colors.accent
                            Accessible.role: Accessible.ListItem
                            Accessible.name: modelData.title + " — " + modelData.caption

                            Behavior on color {
                                ColorAnimation {
                                    duration: Services.Motion.effectsFast
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                }
                            }
                            Behavior on border.width {
                                NumberAnimation {
                                    duration: Services.Motion.effects
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                }
                            }

                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 1

                                Text {
                                    font.family: Services.Fonts.family
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: modelData.title
                                    font.pixelSize: 13
                                    color: Services.Colors.text
                                }
                                Text {
                                    font.family: Services.Fonts.family
                                    width: parent.width
                                    elide: Text.ElideRight
                                    text: modelData.caption
                                    font.pixelSize: 10
                                    color: Services.Colors.textMuted
                                }
                            }

                            MouseArea {
                                id: resMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onEntered: app.searchSel = index
                                onClicked: app.jumpTo(modelData)
                            }
                        }
                    }

                    Text {
                        font.family: Services.Fonts.family
                        visible: searchInput.text.trim() !== ""
                                 && app.searchResults.length === 0
                        x: 14
                        text: "No matches"
                        font.pixelSize: 12
                        color: Services.Colors.textMuted
                    }
                }
            }

            // thumb — only while the page list overflows the window
            Rectangle {
                visible: sidebarFlick.contentHeight > sidebarFlick.height + 1
                anchors.right: parent.right
                anchors.rightMargin: 3
                width: 3
                radius: 1.5
                opacity: 0.7
                color: Services.Colors.accent
                y: sidebarFlick.contentY * (sidebarFlick.height / sidebarFlick.contentHeight)
                height: Math.max(20, sidebarFlick.height
                    * (sidebarFlick.height / sidebarFlick.contentHeight))
            }
        }

        // ——— content header ——— macOS System Settings title bar: the
        // ‹ › history pair on the left, the page name beside it, the
        // close box at the far right. The per-page filter (long pages
        // only) lives here too, right-aligned before close.
        Item {
            id: contentHeader
            anchors.left: sidebarBox.right
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.leftMargin: 16
            anchors.rightMargin: 14
            height: 46

            Row {
                id: navPair
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Repeater {
                    model: [{
                        glyph: "‹",
                        avail: Services.SettingsApp.histBackAvail,
                        tip: "Back (page history)"
                    }, {
                        glyph: "›",
                        avail: Services.SettingsApp.histFwdAvail,
                        tip: "Forward (page history)"
                    }]
                    delegate: Rectangle {
                        required property var modelData
                        width: 26
                        height: 26
                        radius: 8
                        color: navMa.containsMouse && modelData.avail
                            ? Services.Colors.surfaceAlt : "transparent"
                        opacity: modelData.avail ? 1 : 0.3
                        Accessible.role: Accessible.Button
                        Accessible.name: modelData.tip

                        ToolTip.visible: navMa.containsMouse
                        ToolTip.delay: 400
                        ToolTip.text: modelData.tip

                        Text {
                            anchors.centerIn: parent
                            text: modelData.glyph
                            font.family: Services.Fonts.family
                            font.pixelSize: 17
                            color: Services.Colors.text
                        }

                        MouseArea {
                            id: navMa
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: modelData.avail
                            cursorShape: modelData.avail
                                ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: modelData.glyph === "‹"
                                ? Services.SettingsApp.histGo(-1)
                                : Services.SettingsApp.histGo(1)
                        }
                    }
                }
            }

            Text {
                font.family: Services.Fonts.family
                anchors.left: navPair.right
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: app.pageIdx >= 0
                    ? Services.SettingsCatalog.pages[app.pageIdx].name : "Settings"
                font.pixelSize: 15
                font.bold: true
                color: Services.Colors.text
            }

            Text {
                id: closeGlyph
                font.family: Services.Fonts.family
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "󰅖"
                font.pixelSize: 15
                color: Services.Colors.textMuted
                Accessible.role: Accessible.Button
                Accessible.name: "Close settings"

                ToolTip.visible: closeMa.containsMouse
                ToolTip.delay: 400
                ToolTip.text: "Close (Esc)"

                MouseArea {
                    id: closeMa
                    anchors.fill: parent
                    anchors.margins: -8
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: Services.SettingsApp.hide()
                }
            }

            // per-page filter — appears only when the page outgrows the
            // window's comfortable list length (>15 rows); typing narrows
            // rowsList through visibleEntries, sections drop when their
            // group runs dry, and the text is remembered per page
            Item {
                id: filterBar
                anchors.right: closeGlyph.left
                anchors.rightMargin: 14
                anchors.verticalCenter: parent.verticalCenter
                height: app.showFilter ? 28 : 0
                opacity: app.showFilter ? 1 : 0
                visible: opacity > 0.01
                width: 240 + (filterCount.visible ? filterCount.implicitWidth + 10 : 0)

            Behavior on height {
                SpringAnimation { spring: Services.Motion.spatialFastSpring; damping: Services.Motion.spatialFastDamping }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }

            Rectangle {
                id: filterPill
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: 240
                height: 28
                radius: 10
                color: Services.Colors.surface
                border.color: filterInput.activeFocus ? Services.Colors.accent
                                                      : Services.Colors.low
                border.width: 1

                TextInput {
                    id: filterInput
                    font.family: Services.Fonts.family
                    anchors.left: parent.left
                    anchors.right: filterClear.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 10
                    anchors.rightMargin: 4
                    clip: true
                    color: Services.Colors.text
                    font.pixelSize: 12
                    selectionColor: Services.Colors.accent
                    Accessible.role: Accessible.EditableText
                    Accessible.name: "Filter this page"
                    onTextChanged: {
                        if (app.currentPage === "") return
                        const m = Object.assign({}, app.pageFilters)
                        m[app.currentPage] = filterInput.text
                        app.pageFilters = m
                    }

                    Text {
                        font.family: Services.Fonts.family
                        visible: filterInput.text === ""
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Filter this page…"
                        color: Services.Colors.textMuted
                        font.pixelSize: 11
                    }
                }

                Rectangle {
                    id: filterClear
                    visible: filterInput.text !== ""
                    anchors.right: parent.right
                    anchors.rightMargin: 5
                    anchors.verticalCenter: parent.verticalCenter
                    width: visible ? 18 : 0
                    height: 18
                    radius: 9
                    color: filterClearMa.containsMouse ? Services.Colors.surfaceAlt : "transparent"
                    Accessible.role: Accessible.Button
                    Accessible.name: "Clear filter"
                    Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                    Text {
                        font.family: Services.Fonts.family
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 10
                        color: Services.Colors.textMuted
                    }

                    MouseArea {
                        id: filterClearMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            filterInput.text = ""
                            filterInput.forceActiveFocus()
                        }
                    }
                }
            }

            Text {
                id: filterCount
                font.family: Services.Fonts.family
                visible: filterInput.text.trim() !== ""
                anchors.right: filterPill.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                text: app.filterMatches + (app.filterMatches === 1
                    ? " match" : " matches")
                font.pixelSize: 11
                color: Services.Colors.textMuted
            }
            }
        }

        // content — one row per entry of the current page
        ListView {
            id: rowsList
            anchors.left: sidebarBox.right
            anchors.right: parent.right
            anchors.top: contentHeader.bottom
            anchors.bottom: footerCapsule.top
            anchors.leftMargin: 16
            anchors.rightMargin: 20
            anchors.topMargin: 4
            anchors.bottomMargin: 8
            clip: true
            spacing: 0
            model: app.visibleEntries
            visible: app.currentPage !== "about"

            // deep-link still pending → the sizer is still growing (or the
            // row is still springing to height); keep re-arming the settle
            // pass so the final position uses the real viewport
            onHeightChanged: if (app.pendingId !== "") pendingIdle.restart()

            // horizontal offset for the shared-axis slide below — a
            // transform instead of x so the left/right anchors stay put
            transform: Translate { id: pageShift }

            // page switch — M3 forward/backward slide: dip out, then the
            // new page slides in from the side of the next sidebar entry
            // (partial slide + fade, the M3 pattern — screens don't
            // travel the full width) and fades up on the Standard set's
            // 250ms enter / emphasized decelerate: utility navigation
            // wants the quick pair, not the 400ms screen pair.
            SequentialAnimation {
                id: pageSwap
                NumberAnimation {
                    target: rowsList
                    property: "opacity"
                    to: 0
                    duration: Math.max(0, Services.Motion.short2 - 40)
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedAccelerate
                }
                ScriptAction {
                    script: pageShift.x = app.pageDir * 40
                }
                ParallelAnimation {
                    // spatial half springs in — arrives, overshoots a hair,
                    // settles aligned (M3E: spatial motion = springs)
                    SpringAnimation {
                        target: pageShift
                        property: "x"
                        to: 0
                        spring: Services.Motion.bounceSpring
                        damping: Services.Motion.bounceDamping
                    }
                    NumberAnimation {
                        target: rowsList
                        property: "opacity"
                        to: 1
                        duration: Services.Motion.standardEnter
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.standardDecelerate
                    }
                }
            }

            // launcher deep-link: make sure the highlighted row is on screen
            Connections {
                target: Services.SettingsApp
                function onFocusIdChanged() {
                    app.resolveFocus()
                }
                function onPageChanged() {
                    // slide direction follows the sidebar: down the list
                    // = enters from the right, up = from the left
                    app.pageDir = app.pageIdx > app.prevPageIdx ? 1 : -1
                    app.prevPageIdx = app.pageIdx
                    rowsList.positionViewAtBeginning()
                    app.resolveFocus()
                    pageSwap.restart()
                }
            }

            delegate: Rectangle {
                id: row
                readonly property var e: modelData
                readonly property bool linked: Services.SettingsApp.focusId === e.id

                // ——— per-row reset ——— entries carrying a catalog
                // `default` show a small ↺ affordance left of the
                // control zone while the live value drifts from it;
                // rows without a default show nothing
                readonly property bool hasDefault:
                    row.e.default !== undefined && row.e.default !== null
                readonly property bool atDefault: {
                    if (!row.hasDefault) return true
                    const d = row.e.default
                    switch (row.e.type) {
                    case "switch":
                        return app.switchOn(row.e)
                            === (d === true || d === "true" || d === 1)
                    case "choice":
                        return String(app.choiceValue(row.e)) === String(d)
                    case "hyprswitch":
                    case "cmdswitch":
                        return !loader.item ? true
                            : (!!loader.item.on === (d === true || d === "true"))
                    case "buttons":
                        return !loader.item
                            || loader.item.current === null
                            || loader.item.current === undefined ? true
                            : String(loader.item.current) === String(d)
                    case "slider": {
                        if (!loader.item) return true
                        const sc = row.e.scale !== undefined
                            ? Number(row.e.scale) : 1
                        return Math.abs(Number(loader.item.live)
                                        - Number(d)) < 0.005
                    }
                    default:
                        // no cheap read path for this type — hide the
                        // affordance rather than lie about the state
                        return true
                    }
                }
                function resetRow() {
                    const e = row.e
                    switch (e.type) {
                    case "switch":
                        Services.Settings.set(e.key, e.default)
                        break
                    case "choice":
                        app.applyChoice(e, e.default)
                        break
                    case "hyprswitch":
                    case "cmdswitch":
                        if (loader.item && loader.item.resetToDefault)
                            loader.item.resetToDefault()
                        break
                    case "buttons":
                        if (loader.item && loader.item.resetToDefault)
                            loader.item.resetToDefault()
                        break
                    case "slider":
                        // default is in display units — commit() runs the
                        // same baseline/persist/eval path a drag would
                        if (loader.item && loader.item.commit)
                            loader.item.commit(Number(e.default))
                        break
                    default:
                        break
                    }
                }

                Component.onCompleted: {
                    if (app.knownTypes.indexOf(row.e.type) < 0)
                        console.warn("SettingsWindow: unknown row type: "
                            + row.e.type + " (entry " + row.e.id + ")")
                }
                readonly property bool topLabels:
                    e.type === "dropdown" || e.type === "swatches"
                    || e.type === "wallpapers" || row.isCard
                readonly property bool isCard:
                    e.type === "powercard" || e.type === "netcard"
                    || e.type === "timecard" || e.type === "carousel"
                    || e.type === "appmixer" || e.type === "voicecard"
                    || e.type === "keybinds" || e.type === "xcompose"
                    || e.type === "animcard" || e.type === "lockstyle"
                    || e.type === "netlist" || e.type === "btlist"
                // right-side zone the label column must stay clear of
                readonly property int ctlZone: {
                    switch (e.type) {
                    case "carousel":  return 40
                    case "dropdown":  return 290
                    case "slider":    return 260
                    case "textsize":  return 260
                    case "cmdslider": return 208
                    case "buttons":   return 346
                    case "choice":    return 250
                    case "lockstyle": return 40
                    case "swatches":
                    case "wallpapers":
                    case "powercard":
                    case "netcard":
                    case "timecard":
                    case "keybinds":
                    case "xcompose":
                    case "animcard":
                    case "netlist":
                    case "btlist":
                    case "appmixer":
                    case "voicecard": return 40
                    default:          return 210
                    }
                }
                width: rowsList.width
                // a section heading is its own short row: the small-caps
                // label sits at its bottom, the card starts right under
                height: (e.type === "section" ? 36 : 64)
                    + (loader.item && loader.item.extraHeight
                          ? loader.item.extraHeight : 0)
                    + (row.isCard ? 12 : 0)
                color: "transparent"

                // ——— group-card geometry ——— the flat list renders
                // macOS-style inset cards: a section starts a card, the
                // plain rows after it share one rounded container with
                // hairline dividers; self-drawing cards (isCard) break
                // the run and draw their own surface
                readonly property bool firstInGroup: {
                    const l = app.visibleEntries
                    if (index <= 0) return true
                    const p = l[index - 1]
                    return p.type === "section" || app.typeIsOwnCard(p.type)
                }
                readonly property bool lastInGroup: {
                    const l = app.visibleEntries
                    if (index >= l.length - 1) return true
                    const n = l[index + 1]
                    return n.type === "section" || app.typeIsOwnCard(n.type)
                }

                // the group card surface — corners round only on the
                // run's outer edges; hover/deep-link step the fill up
                Rectangle {
                    id: rowCard
                    anchors.fill: parent
                    visible: row.e.type !== "section" && !row.isCard
                    topLeftRadius: row.firstInGroup ? 10 : 0
                    topRightRadius: row.firstInGroup ? 10 : 0
                    bottomLeftRadius: row.lastInGroup ? 10 : 0
                    bottomRightRadius: row.lastInGroup ? 10 : 0
                    color: (hover.hovered || row.linked)
                        ? Services.Colors.surfaceAlt : Services.Colors.surface
                    border.width: row.linked ? 1 : 0
                    border.color: Services.Colors.accent

                    // hover / deep-link highlight fades in and out instead of
                    // popping — effect, so emphasized decelerate
                    Behavior on color {
                        ColorAnimation {
                            duration: Services.Motion.effectsFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }
                    Behavior on border.width {
                        NumberAnimation {
                            duration: Services.Motion.effects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }
                }

                // hairline between the rows of one group — inset from the
                // left like macOS, stops before the run's last row
                Rectangle {
                    visible: row.e.type !== "section" && !row.isCard
                             && !row.lastInGroup
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: Services.Colors.low
                    opacity: 0.4
                }

                Behavior on height {
                    SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping }
                }

                HoverHandler { id: hover }

                // ↺ — subtle until the row is hovered; sits just left
                // of the control zone, so the label column yields 24px
                Item {
                    id: resetBtn
                    anchors.right: parent.right
                    anchors.rightMargin: row.ctlZone + 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    visible: row.hasDefault && !row.atDefault
                             && row.e.type !== "section"
                    opacity: visible ? (hover.containsMouse ? 1 : 0.45) : 0
                    Accessible.role: Accessible.Button
                    Accessible.name: "Reset " + row.e.label + " to default"
                    ToolTip.visible: resetMa.containsMouse
                    ToolTip.delay: 400
                    ToolTip.text: "Reset to default"

                    Behavior on opacity {
                        NumberAnimation {
                            duration: Services.Motion.effectsFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }

                    Rectangle {
                        anchors.fill: parent
                        radius: 10
                        color: resetMa.containsMouse ? Services.Colors.surfaceAlt
                                                     : "transparent"
                        Behavior on color {
                            ColorAnimation {
                                duration: Services.Motion.effectsFast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Services.Motion.emphasizedDecelerate
                            }
                        }
                    }

                    Text {
                        font.family: Services.Fonts.family
                        anchors.centerIn: parent
                        text: "↺"
                        font.pixelSize: 12
                        color: Services.Colors.textMuted
                    }

                    MouseArea {
                        id: resetMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: row.resetRow()
                    }
                }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.top: row.topLabels ? parent.top : undefined
                    anchors.topMargin: row.topLabels ? 13 : 0
                    anchors.verticalCenter: row.topLabels ? undefined : parent.verticalCenter
                    width: parent.width - row.ctlZone
                         - (resetBtn.visible ? 24 : 0)
                    spacing: 3
                    visible: row.e.type !== "section"

                    Text {
                        font.family: Services.Fonts.family
                        text: row.e.label
                        font.pixelSize: 13
                        font.bold: true
                        color: Services.Colors.text
                        elide: Text.ElideRight
                        width: parent.width
                    }
                    Text {
                        font.family: Services.Fonts.family
                        text: row.e.description || ""
                        font.pixelSize: 11
                        color: Services.Colors.textMuted
                        width: parent.width
                        visible: text !== ""
                        // up to two lines at the 64px row height; only
                        // longer copy still elides (never mid-word-…
                        // when it can wrap instead)
                        wrapMode: Text.Wrap
                        maximumLineCount: 2
                        elide: Text.ElideRight
                    }
                }

                // section — the caption that labels the group card
                // under it: tracked small caps, bottom-aligned so the
                // card starts right below (macOS inset-group caption)
                Text {
                    font.family: Services.Fonts.family
                    visible: row.e.type === "section"
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 6
                    text: String(row.e.label || "").toUpperCase()
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 1.2
                    color: Services.Colors.textMuted
                }

                // switch — accent pill + On/Off value text
                Row {
                    visible: row.e.type === "switch"
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    Text {
                        font.family: Services.Fonts.family
                        width: 24
                        height: 24
                        verticalAlignment: Text.AlignVCenter
                        horizontalAlignment: Text.AlignRight
                        text: app.switchOn(row.e) ? "On" : "Off"
                        font.pixelSize: 12
                        font.bold: true
                        color: app.switchOn(row.e) ? Services.Colors.accent
                                                   : Services.Colors.textMuted

                        Behavior on color {
                            ColorAnimation {
                                duration: Services.Motion.effectsFast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Services.Motion.emphasizedDecelerate
                            }
                        }
                    }

                    Rectangle {
                        width: 44
                        height: 24
                        radius: 12
                        color: app.switchOn(row.e) ? Services.Colors.accent : Services.Colors.surface
                        Accessible.role: Accessible.Button
                        Accessible.name: row.e.label + " — " + (app.switchOn(row.e) ? "on" : "off")

                        Behavior on color {
                            ColorAnimation {
                                duration: Services.Motion.effectsFast
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Services.Motion.emphasizedDecelerate
                            }
                        }

                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            x: app.switchOn(row.e) ? parent.width - width - 3 : 3
                            width: 18
                            height: 18
                            radius: 9
                            color: app.switchOn(row.e) ? Services.Colors.background : Services.Colors.textMuted

                            Behavior on color {
                                ColorAnimation {
                                    duration: Services.Motion.effectsFast
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                }
                            }

                            // active-page indicator — bounces over to the new entry
                            Behavior on x {
                                SpringAnimation {
                                    spring: Services.Motion.bounceSpring
                                    damping: Services.Motion.bounceDamping
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: Services.Settings.set(row.e.key, !app.switchOn(row.e))
                        }
                    }
                }

                // choice — segmented chips
                Row {
                    visible: row.e.type === "choice"
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 6

                    Repeater {
                        model: row.e.options

                        delegate: Rectangle {
                            readonly property bool selected: app.choiceValue(row.e) === modelData.value
                            height: 28
                            radius: 14
                            width: optLabel.width + 26
                            color: selected ? Services.Colors.accent
                                : (optMouse.containsMouse ? Services.Colors.surfaceAlt
                                                          : Services.Colors.surface)
                            Accessible.role: Accessible.Button
                            Accessible.name: row.e.label + ": " + modelData.label

                            Behavior on color {
                                ColorAnimation {
                                    duration: Services.Motion.effectsFast
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                }
                            }

                            Text {
                                font.family: Services.Fonts.family
                                id: optLabel
                                anchors.centerIn: parent
                                text: modelData.label
                                font.pixelSize: 12
                                font.bold: selected
                                color: parent.selected ? Services.Colors.background : Services.Colors.textMuted

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Services.Motion.effectsFast
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                    }
                                }
                            }

                            MouseArea {
                                id: optMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: app.applyChoice(row.e, modelData.value)
                            }
                        }
                    }
                }

                // action — tonal button, shells out via qs ipc
                Rectangle {
                    visible: row.e.type === "action"
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    height: 30
                    radius: 15
                    width: actionLabel.width + 30
                    color: actionMouse.containsMouse
                        ? (row.e.destructive ? Services.Colors.critical
                                             : Services.Colors.surfaceAlt)
                        : Services.Colors.surface
                    Accessible.role: Accessible.Button
                    Accessible.name: (row.e.verb || "Open") + " — " + row.e.label

                    Behavior on color {
                        ColorAnimation {
                            duration: Services.Motion.effectsFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }

                    Text {
                        font.family: Services.Fonts.family
                        id: actionLabel
                        anchors.centerIn: parent
                        text: row.e.verb || "Open"
                        font.pixelSize: 12
                        font.bold: true
                        color: Services.Colors.accent
                    }

                    MouseArea {
                        id: actionMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            // catalog marks destructive actions; they get
                            // the confirm card instead of firing blind
                            if (row.e.destructive) {
                                confirmDlg.ask((row.e.verb || "Run")
                                               + " “" + row.e.label + "”?",
                                    row.e.description || "",
                                    row.e.verb || "Confirm",
                                    function() { app.runCommand(row.e) })
                            } else {
                                app.runCommand(row.e)
                            }
                        }
                    }
                }

                // info — read-only value, right aligned
                Text {
                    font.family: Services.Fonts.family
                    visible: row.e.type === "info"
                    anchors.right: parent.right
                    anchors.rightMargin: 16
                    anchors.verticalCenter: parent.verticalCenter
                    text: app.infoValue(row.e)
                    font.pixelSize: 13
                    font.bold: true
                    color: Services.Colors.accent
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 190)
                }

                // the renderer-added types live in their own components;
                // e binds at creation, so each child's onCompleted read
                // already sees its entry (Loader would race otherwise)
                Component { id: compSlider;   SettingsSliderRow     { e: row.e } }
                Component { id: compSwitch;   SettingsHyprSwitchRow { e: row.e } }
                Component { id: compDropdown; SettingsDropdownRow   { e: row.e } }
                Component { id: compSwatch;   SettingsSwatchGrid    { e: row.e } }
                Component { id: compCarousel; SettingsCarouselRow   { e: row.e } }
                Component { id: compButtons;  SettingsButtonsRow    { e: row.e } }
                Component { id: compCmdSw;    SettingsCmdSwitchRow  { e: row.e } }
                Component { id: compPower;    SettingsPowerCard     { e: row.e } }
                Component { id: compNet;      SettingsNetworkCard   { e: row.e } }
                Component { id: compTime;     SettingsTimeCard      { e: row.e } }
                Component { id: compCmdSlider; SettingsCmdSliderRow { e: row.e } }
                Component { id: compAppMixer; SettingsAppMixerCard { e: row.e } }
                Component { id: compVoice;   SettingsVoiceCard    { e: row.e } }
                Component { id: compTextSize; SettingsTextSizeRow   { e: row.e } }
                Component { id: compBinds;    SettingsKeybindsEditor { e: row.e } }
                Component { id: compCompose;  SettingsComposeEditor  { e: row.e } }
                Component { id: compAnim;     SettingsAnimationsCard { e: row.e } }
                Component { id: compNetList;  SettingsNetworksCard   { e: row.e } }
                Component { id: compBtList;   SettingsBluetoothCard  { e: row.e } }
                Component { id: compLockStyle; SettingsLockStyleRow  { e: row.e } }

                Loader {
                    id: loader
                    active: row.e.type === "slider" || row.e.type === "hyprswitch"
                         || row.e.type === "dropdown" || row.e.type === "swatches"
                         || row.e.type === "wallpapers" || row.e.type === "carousel"
                         || row.e.type === "buttons" || row.e.type === "cmdswitch"
                         || row.e.type === "cmdslider" || row.e.type === "textsize"
                         || row.e.type === "lockstyle"
                         || row.isCard
                    sourceComponent: {
                        switch (row.e.type) {
                        case "slider":     return compSlider
                        case "hyprswitch": return compSwitch
                        case "dropdown":   return compDropdown
                        case "swatches":
                        case "wallpapers": return compSwatch
                        case "carousel":   return compCarousel
                        case "buttons":    return compButtons
                        case "cmdswitch":  return compCmdSw
                        case "powercard":  return compPower
                        case "netcard":    return compNet
                        case "timecard":   return compTime
                        case "cmdslider":  return compCmdSlider
                        case "appmixer":   return compAppMixer
                        case "voicecard":  return compVoice
                        case "textsize":   return compTextSize
                        case "keybinds":   return compBinds
                        case "xcompose":   return compCompose
                        case "animcard":   return compAnim
                        case "lockstyle":  return compLockStyle
                        case "netlist":    return compNetList
                        case "btlist":     return compBtList
                        default:
                            // the sourceComponent BINDING evaluates for
                            // every row (inline types included) — only a
                            // genuinely unknown type may log; a catalog
                            // typo shows up here AND in the row's own
                            // Component.onCompleted check, never as a
                            // silently wrong control
                            if (app.knownTypes.indexOf(row.e.type) < 0)
                                console.warn("SettingsWindow: unknown row type: "
                                    + row.e.type + " (entry " + row.e.id + ")")
                            return null
                        }
                    }

                    // grids and cards sit below the labels; the dropdown
                    // grows from its top-right trigger; compact controls
                    // center on the right. Cards anchor on BOTH sides so
                    // their width follows the content column (a width
                    // binding of undefined would zero the item).
                    readonly property bool grid:
                        row.e.type === "swatches" || row.e.type === "wallpapers"
                        || row.isCard
                    anchors.left: grid ? parent.left : undefined
                    anchors.leftMargin: grid ? 14 : 0
                    anchors.top: row.topLabels ? parent.top : undefined
                    anchors.topMargin: row.e.type === "dropdown" ? 17 : 0
                    anchors.right: (!grid || row.isCard) ? parent.right : undefined
                    anchors.rightMargin: 16
                    anchors.verticalCenter: row.topLabels ? undefined : parent.verticalCenter
                }
            }
        }

        // empty state — the page filter matched nothing
        Text {
            font.family: Services.Fonts.family
            anchors.centerIn: rowsList
            visible: rowsList.visible && app.showFilter
                     && filterInput.text.trim() !== ""
                     && app.visibleEntries.length === 0
            text: "0 matches"
            font.pixelSize: 12
            color: Services.Colors.textMuted
        }

        // About page = power-style cards (grouped fastfetch info) —
        // theme/wallpaper selectors live as cards on Appearance
        SettingsAboutCards {
            id: aboutCards
            anchors.left: sidebarBox.right
            anchors.right: parent.right
            anchors.top: contentHeader.bottom
            anchors.bottom: footerCapsule.top
            anchors.leftMargin: 16
            anchors.rightMargin: 20
            anchors.topMargin: 8
            anchors.bottomMargin: 8
            visible: app.currentPage === "about"
            ffRows: app.ffRows
        }

        // honest empty/error state — no fastfetch (or no parseable
        // output) used to leave a silently blank page
        Text {
            font.family: Services.Fonts.family
            anchors.centerIn: aboutCards
            visible: app.currentPage === "about" && app.ffDone
                     && app.ffRows.length === 0
            text: "Couldn't read system info — fastfetch missing?"
            font.pixelSize: 12
            color: Services.Colors.textMuted
        }

        // ——————— toasts ——————— snackbar stack inside the window,
        // above the footer: surface + low border, radius 12, 2.5s
        // auto-dismiss, max 3 (the queue lives in the SettingsToast
        // singleton so rows/cards can push without a window reference)
        ListView {
            id: toastStack
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: footerCapsule.top
            anchors.bottomMargin: 8
            width: contentWidth
            height: contentHeight
            spacing: 6
            interactive: false
            model: SettingsToast.queue

            add: Transition {
                NumberAnimation {
                    property: "opacity"
                    from: 0
                    to: 1
                    duration: Services.Motion.effects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
                NumberAnimation {
                    property: "y"
                    duration: Services.Motion.effects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }
            remove: Transition {
                NumberAnimation {
                    property: "opacity"
                    to: 0
                    duration: Services.Motion.effects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedAccelerate
                }
            }
            displaced: Transition {
                NumberAnimation {
                    properties: "y"
                    duration: Services.Motion.effects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }

            delegate: Rectangle {
                id: toastRow
                property var td: modelData
                width: Math.min(toastTxt.implicitWidth + 34, 520)
                height: 30
                radius: 12
                color: Services.Colors.surface
                border.color: toastRow.td && toastRow.td.error
                    ? Services.Colors.critical : Services.Colors.low
                border.width: 1
                Accessible.role: Accessible.AlertMessage
                Accessible.name: toastRow.td ? toastRow.td.text : ""

                Row {
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        font.family: Services.Fonts.family
                        anchors.verticalCenter: parent.verticalCenter
                        text: toastRow.td && toastRow.td.error ? "✕" : "✓"
                        font.pixelSize: 11
                        color: toastRow.td && toastRow.td.error
                            ? Services.Colors.critical : Services.Colors.accent
                    }
                    Text {
                        id: toastTxt
                        font.family: Services.Fonts.family
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 470)
                        elide: Text.ElideRight
                        text: toastRow.td ? toastRow.td.text : ""
                        font.pixelSize: 12
                        color: Services.Colors.text
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (toastRow.td) SettingsToast.drop(toastRow.td.id)
                }

                Timer {
                    id: toastTimer
                    interval: 2500
                    running: toastRow.td !== null && toastRow.td !== undefined
                    onTriggered: if (toastRow.td)
                        SettingsToast.drop(toastRow.td.id)
                }
                // a queue shift re-uses this delegate for a NEW toast —
                // restart its clock so the old deadline can't eat it
                onTdChanged: toastTimer.restart()
            }
        }

        // destructive-action confirmation card — centered over the
        // window (SettingsConfirmDialog.qml holds the ask() API)
        SettingsConfirmDialog {
            id: confirmDlg
            anchors.fill: parent
        }

        // ——————— Apply / Revert ——————— hypr slider / hyprKey-button /
        // hyprswitch changes take effect live, but hyprctl eval does not
        // survive a reload. Apply writes the pending set into
        // ~/.config/hypr/user-settings.lua (hyprland.lua loads it last),
        // Revert evals the pre-change baselines back and drops them.
        // Restyled as a floating capsule (macOS button-chrome parity),
        // same behavior: quiet while idle, full presence once pending.
        Rectangle {
            id: footerCapsule
            anchors.right: parent.right
            anchors.rightMargin: 22
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 16
            radius: 17
            color: Services.Colors.surface
            border.color: Services.Colors.low
            border.width: 1
            opacity: Services.SettingsApp.dirty ? 1 : 0.45
            implicitWidth: footer.implicitWidth + 24
            implicitHeight: footer.implicitHeight + 12

            Behavior on opacity {
                NumberAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }

        Row {
            id: footer
            anchors.centerIn: parent
            spacing: 8

            Text {
                font.family: Services.Fonts.family
                anchors.verticalCenter: parent.verticalCenter
                opacity: Services.SettingsApp.dirty ? 1 : 0
                visible: opacity > 0.01
                text: Services.SettingsApp.pendingCount
                    + (Services.SettingsApp.pendingCount === 1
                       ? " change pending" : " changes pending")
                font.pixelSize: 12
                color: Services.Colors.textMuted

                Behavior on opacity {
                    NumberAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }
            }

            Rectangle {
                id: revertBtn
                width: revertLbl.width + 30
                height: 30
                radius: 15
                opacity: Services.SettingsApp.dirty ? 1 : 0.4
                color: revertMa.containsMouse && Services.SettingsApp.dirty
                    ? Services.Colors.surfaceAlt : Services.Colors.surface
                Accessible.role: Accessible.Button
                Accessible.name: "Revert pending changes"

                Behavior on opacity {
                    NumberAnimation {
                        duration: Services.Motion.effects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }

                Text {
                    font.family: Services.Fonts.family
                    id: revertLbl
                    anchors.centerIn: parent
                    text: "Revert"
                    font.pixelSize: 13
                    font.bold: true
                    color: Services.Colors.text
                }
                MouseArea {
                    id: revertMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: Services.SettingsApp.dirty
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        Services.SettingsApp.revertPending()
                        SettingsToast.push("Reverted pending changes")
                    }
                }
            }

            Rectangle {
                id: applyBtn
                width: applyLbl.width + 34
                height: 30
                radius: 15
                opacity: Services.SettingsApp.dirty ? 1 : 0.4
                color: Services.SettingsApp.dirty ? Services.Colors.accent
                    : Services.Colors.surface
                Accessible.role: Accessible.Button
                Accessible.name: "Apply pending changes"

                Behavior on opacity {
                    NumberAnimation {
                        duration: Services.Motion.effects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }
                Behavior on color {
                    ColorAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }

                Text {
                    font.family: Services.Fonts.family
                    id: applyLbl
                    anchors.centerIn: parent
                    text: "Apply"
                    font.pixelSize: 13
                    font.bold: true
                    // on-accent label: contrast-floored so a theme whose
                    // background collapses toward the accent (the same
                    // kanagawa trap as the launcher pill) can't paint an
                    // invisible Apply
                    color: Services.SettingsApp.dirty
                        ? Services.Colors.contrastAgainst(
                              Services.Colors.background, Services.Colors.accent, 4.5)
                        : Services.Colors.text

                    Behavior on color {
                        ColorAnimation {
                            duration: Services.Motion.effectsFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }
                }
                MouseArea {
                    id: applyMa
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: Services.SettingsApp.dirty
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        // count before the call — applyPending() empties
                        // the record the moment it runs
                        const n = Services.SettingsApp.pendingCount
                        Services.SettingsApp.applyPending()
                        SettingsToast.push(n === 1
                            ? "Applied 1 change — saved for reloads"
                            : "Applied " + n + " changes — saved for reloads")
                    }
                }
            }
        }
        }

        // ——————— resize grip ——————— the window lives inside the bar's
        // overlay, so the macOS resize affordance is this corner grip:
        // drag to grow, geometry clamps in SettingsApp and persists
        // after the drag goes quiet
        Item {
            id: resizeGrip
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            width: 20
            height: 20

            Canvas {
                id: gripMarks
                anchors.fill: parent
                anchors.margins: 4
                opacity: gripMa.containsMouse ? 0.9 : 0.45

                Behavior on opacity {
                    NumberAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }

                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.strokeStyle = Qt.rgba(Services.Colors.textMuted.r,
                        Services.Colors.textMuted.g, Services.Colors.textMuted.b, 1)
                    ctx.lineWidth = 1.5
                    ctx.lineCap = "round"
                    for (let i = 0; i < 3; i++) {
                        const o = i * 4
                        ctx.beginPath()
                        ctx.moveTo(width - o - 1, 1)
                        ctx.lineTo(1, height - o - 1)
                        ctx.stroke()
                    }
                }
            }

            MouseArea {
                id: gripMa
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.SizeFDiagCursor
                property real startX: 0
                property real startY: 0
                property real startW: 0
                property real startH: 0
                onPressed: (m) => {
                    gripMa.startX = m.x
                    gripMa.startY = m.y
                    gripMa.startW = Services.SettingsApp.winW
                    gripMa.startH = Services.SettingsApp.winH
                }
                onPositionChanged: (m) => {
                    if (!pressed) return
                    Services.SettingsApp.setWinSize(
                        gripMa.startW + (m.x - gripMa.startX),
                        gripMa.startH + (m.y - gripMa.startY))
                }
            }
        }
    }
}
