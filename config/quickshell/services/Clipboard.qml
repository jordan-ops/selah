pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Native clipboard manager (no cliphist): `wl-paste --watch` pipes every
// new selection byte-exact into scripts/clipboard-watch.sh, which appends
// one line to ~/.local/state/quickshell/clipboard/index — ts, path, hash,
// mime, size, one-line preview. That index is the whole state: FileView
// watches it here, and the same file is the persistence across restarts
// (the watcher replays the live clipboard on start, deduped by hash).
//
// Panel contract: click a row -> copy it + close the pill (paste with
// Ctrl+V wherever you're going); the "clipboard" pill mode is driven by
// `open`. IPC self-tests:
//   qs ipc call clipboard open / copy 0 / preview 0 / count / clear
Singleton {
    id: root

    property bool open: false
    // Multi-monitor: overlay state is shared, but every screen has its own
    // bar. The bar that opens this overlay records itself here and only it
    // reacts — without an owner, every bar showed the panel AND armed its
    // own HyprlandFocusGrab; the duplicate grabs fought over keyboard focus
    // and cleared each other the instant they activated, so no panel ever
    // appeared once a second display was connected.
    property string ownerScreen: ""
    onOpenChanged: {
        if (open) {
            const fm = Hyprland.focusedMonitor
            ownerScreen = fm ? fm.name
                : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
        }
    }


    readonly property string dir:
        Quickshell.env("HOME") + "/.local/state/quickshell/clipboard"
    readonly property string indexPath: dir + "/index"
    readonly property string watchScript: Quickshell.env("HOME")
        + "/.config/quickshell/scripts/clipboard-watch.sh"
    readonly property string ctlScript: Quickshell.env("HOME")
        + "/.config/quickshell/scripts/clipboard-ctl.sh"

    // newest first: { ts, path, mime, size, preview, ext }
    property var entries: []
    // what the panel lists — history minus the search text
    property string filter: ""

    readonly property var filtered: {
        if (filter === "") return entries
        const q = filter.toLowerCase()
        return entries.filter(e =>
            e.preview.toLowerCase().indexOf(q) >= 0
            || e.mime.toLowerCase().indexOf(q) >= 0)
    }

    function parseIndex(text) {
        const out = []
        const lines = text.split("\n")
        for (let i = lines.length - 1; i >= 0; i--) {
            const line = lines[i]
            if (line.length === 0) continue
            const f = line.split("\t")
            if (f.length < 6) continue
            out.push({
                ts: Number(f[0]),
                path: f[1],
                mime: f[3],
                size: Number(f[4]),
                preview: f[5],
                ext: f[1].substring(f[1].lastIndexOf(".") + 1)
            })
        }
        return out
    }

    // A FileView can't attach its watch to a file that doesn't exist yet
    // (first run: the index is created by the first capture — the view
    // would silently never load). So the dir/index are created FIRST, and
    // the FileView is only instantiated after prep exits.
    Process {
        id: prep
        command: ["bash", "-c",
            'mkdir -p "$1/entries"; [ -f "$1/index" ] || : > "$1/index"',
            "qs", root.dir]
        running: true
        onExited: indexLoader.active = true
    }

    Loader {
        id: indexLoader
        active: false
        sourceComponent: indexViewComp
    }

    Component {
        id: indexViewComp
        FileView {
            path: root.indexPath
            printErrors: false
            watchChanges: true
            onFileChanged: reload()
            onLoaded: root.entries = root.parseIndex(text())
        }
    }

    // long-running capture; restart if it ever dies (only expected when
    // the wayland connection itself goes away)
    Process {
        id: watcher
        command: ["wl-paste", "--watch", root.watchScript]
        running: true
        onExited: restartTimer.start()
    }
    Timer { id: restartTimer; interval: 2000; onTriggered: watcher.running = true }

    Process { id: copyProc }
    Process { id: ctlProc }

    function copy(i) {
        const e = filtered[i]
        if (!e) return
        // text goes through the plain path (wl-copy infers text/plain);
        // images/binary keep the exact type they were offered as
        copyProc.command = ["bash", "-c",
            'case "$2" in text/*|"") wl-copy < "$1" ;; *) wl-copy -t "$2" < "$1" ;; esac',
            "qs", e.path, e.mime]
        copyProc.running = true
        root.close()
    }

    function remove(i) {
        const e = filtered[i]
        if (!e) return
        ctlProc.command = [root.ctlScript, "remove", e.path]
        ctlProc.running = true
    }

    function clear() {
        ctlProc.command = [root.ctlScript, "clear"]
        ctlProc.running = true
    }

    function openPanel() {
        // the pill's modes are exclusive — opening the clipboard dismisses
        // the sibling panels so the mode chain can't show something else
        // under a panel the user just asked for
        Launcher.closeLauncher()
        Themes.closePicker()
        Wallpapers.closePicker()
        ControlCenter.close()
        ClockCard.close()
        PowerMenu.open = false
        filter = ""
        open = true
    }

    function close() { open = false }
    function toggle() { open ? close() : openPanel() }

    // and the reverse: any sibling panel taking the pill closes the
    // clipboard, so `open` never sits true under another mode (which would
    // make the bar glyph and the keybind look dead)
    function dismiss() { if (open) open = false }
    Connections { target: Launcher;     function onOpenChanged() { if (Launcher.open) root.dismiss() } }
    Connections { target: Themes;       function onOpenChanged() { if (Themes.open) root.dismiss() } }
    Connections { target: Wallpapers;   function onOpenChanged() { if (Wallpapers.open) root.dismiss() } }
    Connections { target: ControlCenter; function onOpenChanged() { if (ControlCenter.open) root.dismiss() } }
    Connections { target: ClockCard;    function onOpenChanged() { if (ClockCard.open) root.dismiss() } }
    Connections { target: PowerMenu;    function onOpenChanged() { if (PowerMenu.open) root.dismiss() } }

    IpcHandler {
        target: "clipboard"
        function toggle(): void { root.toggle() }
        function open(): void { root.openPanel() }
        function close(): void { root.close() }
        function count(): string { return String(root.filtered.length) }
        function total(): string { return String(root.entries.length) }
        function preview(index: string): string {
            const e = root.filtered[parseInt(index, 10)]
            return e ? e.preview : ""
        }
        function mime(index: string): string {
            const e = root.filtered[parseInt(index, 10)]
            return e ? e.mime : ""
        }
        function copy(index: string): void { root.copy(parseInt(index, 10)) }
        function remove(index: string): void { root.remove(parseInt(index, 10)) }
        function clear(): void { root.clear() }
        // scripts/search tests without a pointer: qs ipc call clipboard setFilter foo
        function setFilter(q: string): void { root.filter = q }
    }
}
