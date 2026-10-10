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
    property var values: ({
        "bar.restStyle": "compact",
        // the suspended-pill variant (Bar.qml lifts the capsule off the
        // top edge) — off keeps the flush bar every theme expects
        "bar.floating": false,
        "effects.ripple": true,
        "effects.edgelight": true,
        // short chime on high-priority capsule flashes (plug/charge) —
        // Bar's chime(), silenced from Settings ▸ Animations
        "effects.tone": true,
        // post-stop x264 re-encode of screen recordings (the recording
        // card's Compress toggle). ON by default: wf-recorder writes
        // near-lossless x264, which is what made these files huge.
        "recording.compress": true,
        "lock.style": "classic",
        // the desktop clock widget — off until asked for. x/y of -1 mean
        // "never placed": clockBox() centres it instead (see below), so a
        // fresh install and a lock into the Clock style both have
        // something to draw without shipping magic pixel numbers.
        "clock.enabled": false,
        "clock.x": -1,
        "clock.y": -1,
        "clock.w": 640,
        "clock.h": 280,
        "clock.format": "hh:mm AP - MM/dd",
        "clock.glow": true,
        // the Nebula widget layer (widgets/): ON by default so a fresh
        // install shows nothing yet (every show* family key is unset =
        // off) but the studio and quick-add are reachable immediately
        "widgets.showWidgets": true
    })

    // typed accessor for keys the shell binds on — one line per new key
    readonly property string barRestStyle: values["bar.restStyle"] || "compact"
    // Suspended pill variant: the capsule hovers just below the screen
    // edge instead of sitting flush on it. Settings ▸ Bar ▸ Floating
    // pill, or `qs ipc call settings set bar.floating true`.
    readonly property bool barFloating:
        values["bar.floating"] === true || values["bar.floating"] === "true"
    // The gap itself, in px — ONE number, shared by Bar.qml (the pill's
    // top offset and the reserved strip) and by anything that has to
    // GUESS the pill's position without the bar having published it
    // (BarMetrics' fallback rect below). Keeping it here is what stops
    // the notification glow sitting flush on the edge while the capsule
    // floats.
    readonly property int barFloatGap: 8
    // iPhone-style % number on the battery ring — hidden until toggled
    readonly property bool barBatteryText:
        values["bar.batteryText"] === true || values["bar.batteryText"] === "true"
    // the capsule's alert chime (Bar.qml) — off means the flash still
    // happens, just silently
    readonly property bool effectsTone:
        values["effects.tone"] === undefined || values["effects.tone"] === true
        || values["effects.tone"] === "true"
    // Compress toggle on the recording card (ScreenRecording) — "default
    // true, tolerate the strings IPC writes over the wire", same reading
    // style as effectsTone/widgetsShow.
    readonly property bool recordingCompress:
        values["recording.compress"] === undefined
        || values["recording.compress"] === true
        || values["recording.compress"] === "true"
    // master switch for the widget layer (widgets/WidgetScreen) — mirrors
    // effectsTone's "default true, tolerate IPC strings" reading
    readonly property bool widgetsShow:
        values["widgets.showWidgets"] === undefined || values["widgets.showWidgets"] === true
        || values["widgets.showWidgets"] === "true"
    // which lock layout lock/ draws — written by Settings ▸ Lock screen,
    // read live by LockScreen's Loader. Unknown values fall back to the
    // original layout rather than to a blank lock surface.
    readonly property string lockStyle: {
        const v = String(values["lock.style"] || "")
        return ["classic", "card", "minimal", "magazine", "clock"].indexOf(v) >= 0
            ? v : "classic"
    }

    // ——— the desktop clock widget (Background.qml + lock/ Clock.qml) ———
    readonly property bool clockEnabled:
        values["clock.enabled"] === true || values["clock.enabled"] === "true"
    readonly property string clockFormat:
        String(values["clock.format"] || "") || "hh:mm AP - MM/dd"
    readonly property bool clockGlow:
        values["clock.glow"] === undefined || values["clock.glow"] === true
        || values["clock.glow"] === "true"

    // ONE source of truth for where the widget sits. Both of its homes
    // ask here — the desktop copy (Background.qml) and the Clock lock
    // style — so what you drag into place on the desktop is exactly
    // what locks, at the same size.
    //
    //   screenW/H   the surface it's being placed on (the preview passes
    //               its design canvas, so the card shows the real thing)
    //   reserve     px the lock needs BELOW the box for date + prompt;
    //               0 on the desktop, ~210 on the lock
    //
    // x/y of -1 (never placed), a non-number, or a value that would put
    // the box off-screen all fall through to "centre it in what's left",
    // and everything is clamped afterwards — a widget saved on a bigger
    // monitor can never land outside a smaller one.
    function clockBox(screenW, screenH, reserve) {
        const r = isFinite(Number(reserve)) ? Number(reserve) : 0
        const bw = Number(values["clock.w"]), bh = Number(values["clock.h"])
        const w = Math.max(160, Math.min(isFinite(bw) ? bw : 640, screenW))
        const h = Math.max(60, Math.min(isFinite(bh) ? bh : 280, screenH))
        const maxX = Math.max(0, screenW - w)
        const maxY = Math.max(0, screenH - h - r)
        let x = Number(values["clock.x"]), y = Number(values["clock.y"])
        if (!isFinite(x) || x < 0) x = maxX / 2
        if (!isFinite(y) || y < 0) y = maxY / 2
        return Qt.rect(Math.round(Math.max(0, Math.min(x, maxX))),
                       Math.round(Math.max(0, Math.min(y, maxY))),
                       Math.round(w), Math.round(h))
    }

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

    // Several keys in ONE write — the drag/resize exit of the desktop
    // clock commits x/y/w/h together, and four set() calls in a row would
    // race the same writeProc (the 2nd..4th `running = true` land while
    // the first bash printf is still going and get dropped, leaving a
    // half-updated file). Values are already typed here (QML numbers and
    // bools), so unlike set() there is no string to parse.
    function setAll(map) {
        const next = {}
        Object.assign(next, root.values, map)
        root.values = next

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
        // Arrays can't ride `set`: `qs ipc call` SPREADS json-array
        // arguments, so `set k '["a"]'` hands over each element (or
        // nothing at all for '[]' — "too few arguments"). This variant
        // takes the payload quote-wrapped — '"[\"a\"]"' parses to a
        // STRING at the cli, passes through as ONE argument — and
        // unwraps the extra json layer before the store parses again.
        // Clearing: qs ipc call settings setList launcher.hidden '"[]"'
        function setList(key: string, value: string): void {
            try { root.set(key, JSON.parse(value)) }
            catch (e) { console.log("settings setList:", key, e) }
        }
    }
}
