pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Seed of the future settings app: one JSON store for shell-wide user
// preferences. The shell binds on typed accessors below (barRestStyle…);
// anything writes through set(), which persists settings.json in place —
// same in-place lesson as colors.json/current-wallpaper, so the FileView
// watch survives. The settings app you build later only needs UI over
// this IPC, which scripts and hypr binds can already use today:
//   qs ipc call settings set bar.restStyle wide
//   qs ipc call settings get bar.restStyle
Singleton {
    id: root

    readonly property string path:
        Quickshell.env("HOME") + "/.local/state/quickshell/settings.json"

    // raw store — defaults live here, loaded file merges over them
    property var values: ({ "bar.restStyle": "compact" })

    // typed accessor for keys the shell binds on — one line per new key
    readonly property string barRestStyle: values["bar.restStyle"] || "compact"
    // iPhone-style % number on the battery ring — hidden until toggled
    readonly property bool barBatteryText:
        values["bar.batteryText"] === true || values["bar.batteryText"] === "true"

    function get(key, dflt) {
        return values[key] !== undefined ? values[key] : dflt
    }

    function set(key, val) {
        // IPC hands everything over as strings — coerce "42"/"true"-ish
        // values back to typed JSON, keep plain words as strings
        let parsed = val
        try { parsed = JSON.parse(val) } catch (e) { parsed = val }

        const next = {}
        Object.assign(next, root.values)
        next[key] = parsed
        root.values = next   // reassign = one notification for every binding

        writeProc.command = ["bash", "-c",
            'printf %s "$1" > "$2"', "qs",
            JSON.stringify(next), root.path]
        writeProc.running = true
    }

    Process { id: writeProc }

    // Convergence path, same pattern as Colors/Wallpapers/Themes: IPC
    // writes hit the file, the inotify watch re-loads it inside the
    // running shell — every writer converges here, so the bar's bindings
    // always follow settings.json instead of freezing at start-up state.
    FileView {
        path: root.path
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const loaded = JSON.parse(text())
                root.values = Object.assign({}, root.values, loaded)
            } catch (e) {
                console.log("Settings: failed to parse", e)
            }
        }
    }

    IpcHandler {
        target: "settings"
        function set(key: string, value: string): void {
            root.set(key, value)
        }
        function get(key: string): string {
            return String(root.get(key, ""))
        }
    }
}
