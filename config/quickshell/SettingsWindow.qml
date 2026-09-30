import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// The settings app window's content: sidebar pages + rows rendered by
// type. It draws and routes only — every value it shows or writes lives
// in services/ (Settings, Themes, …) or goes out through qs ipc exactly
// like the hypr binds do. Which settings exist is not this file's
// business: services/SettingsCatalog.qml is the one list, and the
// launcher indexes that same list (omasettings' one-source rule).
FocusScope {
    id: app
    width: 1000
    height: 640
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
        const i = app.pageEntries.findIndex(e => e.id === app.pendingId)
        if (i >= 0 && rowsList.height > 100)
            rowsList.positionViewAtIndex(i, ListView.Contain)
        pendingIdle.restart()
    }

    Timer {
        id: pendingIdle
        interval: 400   // past both the sizer spring and the row-height spring
        onTriggered: {
            if (app.pendingId === "") return
            const i = app.pageEntries.findIndex(e => e.id === app.pendingId)
            if (i >= 0 && rowsList.height > 100)
                rowsList.positionViewAtIndex(i, ListView.Contain)
            app.pendingId = ""
        }
    }

    // ——— sidebar reveal: pages past the visible slice (Login screen,
    // Default apps, Neovim, About) sit below the sidebar's bottom edge, so
    // the active highlight ended up off-screen after a deep-link. Slide the
    // flick just far enough to contain the active row — M3 standard set's
    // quick pair, same easing as the panel — and no-op when the row is
    // already visible, so every hook (page switch, settle, search clear)
    // is idempotent.
    function revealSidebarRow() {
        if (!sidebarFlick || sidebarFlick.height <= 10
            || sidebarFlick.contentHeight <= sidebarFlick.height) return
        const rowH = 36 + sidebarCol.spacing
        const rowTop = app.pageIdx * rowH
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

    onCurrentPageChanged: revealSidebarRow()

    // ——— About page: live fastfetch details, fed into the normal info
    // rows (label/value) instead of the old curated content. Cached after
    // the first run — fastfetch takes ~60ms and the page-swap dip covers
    // the brief fill-in.
    property var ffRows: []

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
    // description / keywords across every page; picking a hit jumps via
    // the existing page + focusId deep-link (rowsList scrolls it into
    // view and flashes it) ———
    readonly property var searchResults: {
        const q = searchInput.text.trim().toLowerCase()
        if (q === "") return []
        const out = []
        const pages = Services.SettingsCatalog.pages
        for (let i = 0; i < pages.length && out.length < 4; i++)
            if (pages[i].name.toLowerCase().includes(q))
                out.push({ kind: "page", title: pages[i].name,
                           caption: "Page", page: pages[i].id, fid: "" })
        const all = Services.SettingsCatalog.entries
        for (let i = 0; i < all.length && out.length < 14; i++) {
            const e = all[i]
            if (!e.label) continue
            const hay = (e.label + " " + (e.description || "") + " "
                         + (e.keywords || "")).toLowerCase()
            if (!hay.includes(q)) continue
            let pname = e.page
            for (let j = 0; j < pages.length; j++)
                if (pages[j].id === e.page) pname = pages[j].name
            out.push({ kind: "entry", title: e.label, caption: pname,
                       page: e.page, fid: e.id || "" })
        }
        return out
    }

    function jumpTo(r) {
        Services.SettingsApp.page = r.page
        if (r.kind === "entry" && r.fid) {
            // reset-then-set so the deep-link fires even when the target
            // row lives on the page we're already viewing
            Services.SettingsApp.focusId = ""
            Services.SettingsApp.focusId = r.fid
        }
        searchInput.text = ""
    }

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

    Process { id: actionRunner }
    function runCommand(cmd) {
        actionRunner.command = cmd
        actionRunner.running = true
    }

    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            Services.SettingsApp.hide()
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
        color: Services.Colors.background
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

        Text {
            font.family: Services.Fonts.family
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.top: parent.top
            anchors.topMargin: 15
            text: "Settings"
            font.pixelSize: 17
            font.bold: true
            color: Services.Colors.text
        }

        Text {
            font.family: Services.Fonts.family
            anchors.right: parent.right
            anchors.rightMargin: 18
            anchors.top: parent.top
            anchors.topMargin: 13
            text: "󰅖"
            font.pixelSize: 15
            color: Services.Colors.textMuted

            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                cursorShape: Qt.PointingHandCursor
                onClicked: Services.SettingsApp.hide()
            }
        }

        Rectangle {
            id: headerLine
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.topMargin: 48
            height: 1
            color: Services.Colors.surface
        }

        // sidebar — pages straight from the catalog; wheel/drag scroll
        // when the page list outgrows the window (16 pages at 500px)
        Item {
            id: sidebarBox
            anchors.left: parent.left
            anchors.top: headerLine.bottom
            anchors.bottom: parent.bottom
            anchors.topMargin: 12
            width: 184

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
                    onAccepted: if (app.searchResults.length > 0) app.jumpTo(app.searchResults[0])

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
                    Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                    Text {
                        font.family: Services.Fonts.family
                        anchors.centerIn: parent
                        text: "✕"
                        font.pixelSize: 9
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
                            x: 10
                            width: sidebarCol.width - 20
                            height: 36
                            radius: 10
                            color: active ? Services.Colors.surface : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Services.Motion.effectsFast
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                }
                            }

                            Text {
                                font.family: Services.Fonts.family
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.name
                                font.pixelSize: 13
                                font.bold: parent.active
                                color: parent.active ? Services.Colors.accent : Services.Colors.textMuted

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Services.Motion.effectsFast
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                    }
                                }
                            }

                            Rectangle {
                                // grows out of the left edge when its page is
                                // picked, retracts when another page takes over
                                visible: width > 0.5
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.active ? 3 : 0
                                height: 16
                                radius: 1.5
                                color: Services.Colors.accent

                                Behavior on width {
                                    SpringAnimation { spring: Services.Motion.spatialFastSpring; damping: Services.Motion.spatialFastDamping }
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
                            x: 10
                            width: sidebarCol.width - 20
                            height: 40
                            radius: 10
                            color: resMa.containsMouse ? Services.Colors.surface : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Services.Motion.effectsFast
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

        // content — one row per entry of the current page
        ListView {
            id: rowsList
            anchors.left: sidebarBox.right
            anchors.right: parent.right
            anchors.top: headerLine.bottom
            anchors.bottom: footer.top
            anchors.leftMargin: 16
            anchors.rightMargin: 20
            anchors.topMargin: 10
            anchors.bottomMargin: 8
            clip: true
            spacing: 4
            model: app.pageEntries
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
                readonly property bool topLabels:
                    e.type === "dropdown" || e.type === "swatches"
                    || e.type === "wallpapers" || row.isCard
                readonly property bool isCard:
                    e.type === "powercard" || e.type === "netcard"
                    || e.type === "timecard" || e.type === "carousel"
                    || e.type === "knobcard"
                    || e.type === "keybinds" || e.type === "xcompose"
                    || e.type === "animcard"
                // right-side zone the label column must stay clear of
                readonly property int ctlZone: {
                    switch (e.type) {
                    case "carousel":  return 40
                    case "dropdown":  return 290
                    case "slider":    return 260
                    case "textsize":  return 260
                    case "knob":      return 96
                    case "buttons":   return 346
                    case "choice":    return 250
                    case "swatches":
                    case "wallpapers":
                    case "powercard":
                    case "netcard":
                    case "timecard":
                    case "knobcard":
                    case "keybinds":
                    case "xcompose":
                    case "animcard":   return 40
                    default:          return 210
                    }
                }
                width: rowsList.width
                height: 64 + (loader.item && loader.item.extraHeight
                              ? loader.item.extraHeight : 0)
                radius: 10
                color: hover.hovered || row.linked ? Services.Colors.surface : "transparent"
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

                Behavior on height {
                    SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping }
                }

                HoverHandler { id: hover }

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: 14
                    anchors.top: row.topLabels ? parent.top : undefined
                    anchors.topMargin: row.topLabels ? 13 : 0
                    anchors.verticalCenter: row.topLabels ? undefined : parent.verticalCenter
                    width: parent.width - row.ctlZone
                    spacing: 3

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
                        elide: Text.ElideRight
                        width: parent.width
                        visible: text !== ""
                    }
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
                    color: actionMouse.containsMouse ? Services.Colors.surfaceAlt
                                                     : Services.Colors.surface

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
                        onClicked: app.runCommand(row.e.command)
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
                Component { id: compKnob;     SettingsKnobRow       { e: row.e } }
                Component { id: compKnobCard; SettingsKnobCard      { e: row.e } }
                Component { id: compTextSize; SettingsTextSizeRow   { e: row.e } }
                Component { id: compBinds;    SettingsKeybindsEditor { e: row.e } }
                Component { id: compCompose;  SettingsComposeEditor  { e: row.e } }
                Component { id: compAnim;     SettingsAnimationsCard { e: row.e } }

                Loader {
                    id: loader
                    active: row.e.type === "slider" || row.e.type === "hyprswitch"
                         || row.e.type === "dropdown" || row.e.type === "swatches"
                         || row.e.type === "wallpapers" || row.e.type === "carousel"
                         || row.e.type === "buttons" || row.e.type === "cmdswitch"
                         || row.e.type === "knob" || row.e.type === "textsize"
                         || row.isCard
                    sourceComponent: {
                        switch (row.e.type) {
                        case "slider":     return compSlider
                        case "hyprswitch": return compSwitch
                        case "dropdown":   return compDropdown
                        case "carousel":   return compCarousel
                        case "buttons":    return compButtons
                        case "cmdswitch":  return compCmdSw
                        case "powercard":  return compPower
                        case "netcard":    return compNet
                        case "timecard":   return compTime
                        case "knob":       return compKnob
                        case "knobcard":   return compKnobCard
                        case "textsize":   return compTextSize
                        case "keybinds":   return compBinds
                        case "xcompose":   return compCompose
                        case "animcard":   return compAnim
                        default:           return compSwatch
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

        // About page = power-style cards (grouped fastfetch info) —
        // theme/wallpaper selectors live as cards on Appearance
        SettingsAboutCards {
            anchors.left: sidebarBox.right
            anchors.right: parent.right
            anchors.top: headerLine.bottom
            anchors.bottom: footer.top
            anchors.leftMargin: 16
            anchors.rightMargin: 20
            anchors.topMargin: 10
            anchors.bottomMargin: 8
            visible: app.currentPage === "about"
            ffRows: app.ffRows
        }

        // ——————— Apply / Revert ——————— hypr slider / hyprKey-button /
        // hyprswitch changes take effect live, but hyprctl eval does not
        // survive a reload. Apply writes the pending set into
        // ~/.config/hypr/user-settings.lua (hyprland.lua loads it last),
        // Revert evals the pre-change baselines back and drops them.
        // Scoped to Appearance only — everywhere else it was pure chrome.
        Row {
            id: footer
            anchors.right: parent.right
            anchors.rightMargin: 20
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            spacing: 8
            opacity: app.currentPage === "appearance" ? 1 : 0
            visible: opacity > 0.01

            Behavior on opacity {
                NumberAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }

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
                width: revertLbl.width + 30
                height: 30
                radius: 15
                opacity: Services.SettingsApp.dirty ? 1 : 0.4
                color: revertMa.containsMouse && Services.SettingsApp.dirty
                    ? Services.Colors.surfaceAlt : Services.Colors.surface

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
                    onClicked: Services.SettingsApp.revertPending()
                }
            }

            Rectangle {
                width: applyLbl.width + 34
                height: 30
                radius: 15
                opacity: Services.SettingsApp.dirty ? 1 : 0.4
                color: Services.SettingsApp.dirty ? Services.Colors.accent
                    : Services.Colors.surface

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
                    color: Services.SettingsApp.dirty ? Services.Colors.background
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
                    onClicked: Services.SettingsApp.applyPending()
                }
            }
        }
    }
}
