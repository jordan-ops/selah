pragma Singleton

import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Layout overview (SUPER + TAB → `qs ipc call overview toggle`), a niri-style
// zoomed-out map of every workspace and its windows. Each workspace is a card
// shaped like its monitor, each window a themed rectangle at its TRUE on-screen
// position and size, scaled down — a schematic floor-plan that is always
// accurate. On top of that, the FOCUSED workspace's card shows a real capture
// of that monitor (grim), so the app you're actually in is rendered as pixels;
// the schematic rectangles stay on top as clickable outlines. Quickshell is a
// client, so unlike niri/HyperScrollview (in-compositor) it can only capture
// what is currently on screen — other workspaces keep the pure schematic.
//
// Capture timing: grim grabs the composited output INCLUDING any overlay we've
// mapped, so the capture MUST run before this surface appears (measured: screen
// brightness 25.5 → 16.1 with the overview up — that's our own scrim). So
// open() fires grim first and only reveals once the frame lands; a 600 ms
// fallback reveals the schematic anyway if grim hangs (never a stale frame).
//
// This singleton owns the state, the geometry model and the capture; Overview.qml
// (the root panel) only draws it. The window list mirrors Hyprland.toplevels and
// re-reads on the same socket2 events Tuck.qml listens for, so windows opened
// or closed elsewhere drop in and out on their own.
Singleton {
    id: root

    property bool open: false
    property string ownerScreen: ""

    // latest clean capture — the focused card's Image points here
    property string shot: ""
    property string shotMonitor: ""
    property int shotSeq: 0        // bumps to force the Image to re-decode
    property string captureMonitor: ""

    function shotPath() {
        const dir = Quickshell.env("XDG_RUNTIME_DIR")
        const base = dir && dir !== "" ? dir : "/tmp"
        return base + "/selah-overview-" + root.captureMonitor + ".png"
    }

    // Open: refresh the window list, then capture the focused monitor BEFORE
    // mapping the surface (see header). Reveal happens in captureProc.onExited,
    // or by the fallback below if grim never returns.
    function beginOpen() {
        if (open) return
        Hyprland.refreshToplevels()
        const fm = Hyprland.focusedMonitor
        const mon = fm ? fm.name
            : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
        ownerScreen = mon
        captureMonitor = mon
        shot = ""                    // drop the previous frame; no stale pixels
        shotMonitor = ""
        captureProc.command = ["sh", "-c",
            "grim -o '" + mon + "' '" + shotPath() + "'"]
        captureFallback.restart()
        captureProc.running = true
    }

    function reveal() {
        captureFallback.stop()
        root.resetSelection()
        open = true
    }

    function addr(a) {
        const s = String(a ?? "")
        return s.startsWith("0x") ? s : "0x" + s
    }

    // Monitor geometry keyed by name. Window `at`/`size` from hyprctl live in
    // the same logical global space as HyprlandMonitor x/y/width/height, so a
    // window's position inside its monitor is just (at - monitor origin).
    readonly property var monitorsByName: {
        const m = {}
        for (const mon of (Hyprland.monitors?.values ?? []))
            m[mon.name] = { x: mon.x, y: mon.y, width: mon.width, height: mon.height }
        // fall back to quickshell's screens for anything Hyprland didn't list
        for (const s of Quickshell.screens)
            if (!m[s.name])
                m[s.name] = { x: s.x, y: s.y, width: s.width, height: s.height }
        return m
    }

    readonly property string focusedAddress: {
        const t = Hyprland.activeToplevel
        return t ? root.addr(t.address) : ""
    }

    function windowsForWorkspace(wsId, mon) {
        const out = []
        for (const t of Hyprland.toplevels.values) {
            const ipc = t.lastIpcObject ?? {}
            if (ipc.mapped === false || ipc.hidden === true)
                continue
            if (ipc.workspace?.id !== wsId)
                continue
            out.push({
                address: root.addr(t.address ?? ipc.address),
                cls: ipc.class ?? "",
                title: t.title ?? ipc.title ?? "",
                x: ipc.at?.[0] ?? 0,
                y: ipc.at?.[1] ?? 0,
                w: ipc.size?.[0] ?? 1,
                h: ipc.size?.[1] ?? 1,
                floating: !!ipc.floating
            })
        }
        return out
    }

    // Every non-special workspace, sorted by id, each carrying its monitor's
    // bounds and the windows sitting on it. Special workspaces (scratchpads,
    // the tuck stash) are excluded — they aren't part of the layout.
    //
    // stripLeft/stripTop/stripW/stripH are the union of the monitor AND every
    // window on it. In the scrolling layout windows tile horizontally past the
    // monitor's right edge (e.g. 4 apps spanning x=10→3814 on a 1920 screen),
    // so the card must represent the whole strip — the monitor border is drawn
    // INSIDE it, and off-screen apps bleed past that border.
    readonly property var workspaces: {
        const list = Hyprland.workspaces.values.filter(w =>
            !String(w.name ?? "").startsWith("special:"))
        const out = list.map(w => {
            const name = String(w.monitor ?? "")
            const mon = root.monitorsByName[name]
                ?? root.monitorsByName[Hyprland.focusedMonitor?.name]
                ?? { x: 0, y: 0, width: 1920, height: 1080 }
            const wins = root.windowsForWorkspace(w.id, mon)
            // strip = union of monitor rect and all window rects (global coords)
            let l = mon.x, t = mon.y, r = mon.x + mon.width, b = mon.y + mon.height
            for (const win of wins) {
                l = Math.min(l, win.x); t = Math.min(t, win.y)
                r = Math.max(r, win.x + win.w); b = Math.max(b, win.y + win.h)
            }
            return {
                id: w.id,
                name: String(w.name ?? w.id),
                monitor: name,
                monitorX: mon.x,
                monitorY: mon.y,
                monitorW: mon.width,
                monitorH: mon.height,
                stripLeft: l,
                stripTop: t,
                stripW: Math.max(1, r - l),
                stripH: Math.max(1, b - t),
                focused: Hyprland.focusedWorkspace?.id === w.id,
                windows: wins
            }
        })
        out.sort((a, b) => a.id - b.id)
        return out
    }

    // ---- keyboard selection ----
    // Arrow keys pick out ONE window: a workspace index plus a window index
    // within that workspace's left-to-right order. selAddr is the picked
    // window's address ("" = empty workspace / nothing picked) — that's what
    // the panel highlights and Enter jumps to. Owning it here (not in the
    // panel) keeps it reachable from delegates, which shadow `win` locally.
    property int selWs: 0
    property int selWin: 0

    function windowsSorted(ws) {
        if (!ws) return []
        return ws.windows.slice().sort((a, b) => (a.x - b.x) || (a.y - b.y))
    }
    readonly property var sortedWins: root.windowsSorted(root.workspaces[root.selWs])
    readonly property string selAddr: {
        const w = root.sortedWins[root.selWin]
        return w ? w.address : ""
    }

    // land on the workspace + window the user is actually in
    function resetSelection() {
        const ws = root.workspaces
        let si = ws.findIndex(w => w.focused)
        si = si >= 0 ? si : 0
        selWs = si
        const sw = root.windowsSorted(ws[si])
        let wi = sw.findIndex(w => w.address === root.focusedAddress)
        selWin = wi >= 0 ? wi : 0
    }

    // Left/Right step through windows left→right, running on into the
    // neighbouring workspace at the ends (niri / HyperScrollview style).
    function navLeft() {
        if (selWin > 0) { selWin--; return }
        if (selWs > 0) {
            selWs--
            selWin = Math.max(0, root.windowsSorted(root.workspaces[selWs]).length - 1)
        }
    }
    function navRight() {
        if (selWin < root.sortedWins.length - 1) { selWin++; return }
        if (selWs < root.workspaces.length - 1) { selWs++; selWin = 0 }
    }

    // Up/Down jump between workspace cards.
    function navUp()   { root.navWorkspace(-1) }
    function navDown() { root.navWorkspace(1) }
    function navWorkspace(d) {
        const i = selWs + d
        if (i < 0 || i >= root.workspaces.length) return
        selWs = i
        const sw = root.windowsSorted(root.workspaces[i])
        const fi = sw.findIndex(w => w.address === root.focusedAddress)
        selWin = fi >= 0 ? fi : Math.min(selWin, sw.length - 1)
        if (selWin < 0) selWin = 0
    }

    // Enter: jump to the selected window (or just its workspace when empty).
    function activateSelection() {
        if (root.selAddr !== "") { root.focusWindow(root.selAddr); return }
        const ws = root.workspaces[root.selWs]
        if (ws) root.switchWorkspace(ws.id)
    }

    readonly property int windowCount: {
        let n = 0
        for (const w of workspaces) n += w.windows.length
        return n
    }

    function focusWindow(address) {
        Hyprland.dispatch(`hl.dsp.focus({ window = "address:${address}" })`)
        close()
    }

    function switchWorkspace(id) {
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${id} })`)
        close()
    }

    function toggle() { open ? close() : beginOpen() }
    function close() {
        captureFallback.stop()
        if (captureProc.running) captureProc.running = false
        if (open) open = false
    }

    // grim writes the frame to a file; on success we publish it so the focused
    // card's Image can fade it in, then reveal. On failure (or a hang caught by
    // the fallback) we still reveal — the schematic is a complete overview on
    // its own, real pixels are only an enhancement.
    Process {
        id: captureProc
        onExited: (code) => {
            if (code === 0) {
                root.shot = root.shotPath()
                root.shotMonitor = root.captureMonitor
                root.shotSeq++
            }
            root.reveal()
        }
    }

    // never wedge the overview shut if grim hangs (e.g. mid-GPU-reset)
    Timer {
        id: captureFallback
        interval: 600
        onTriggered: root.reveal()
    }

    Timer {
        id: refresh
        interval: 250
        onTriggered: Hyprland.refreshToplevels()
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (["closewindow", "movewindowv2", "openwindow", "windowtitlev2",
                 "createworkspacev2", "destroyworkspacev2", "moveworkspacev2"]
                .indexOf(event.name) >= 0)
                refresh.restart()
        }
    }

    Connections {
        target: Hyprland.toplevels
        function onValuesChanged() { refresh.restart() }
    }

    IpcHandler {
        target: "overview"
        function toggle(): void { root.toggle() }
        function status(): bool { return root.open }
    }
}
