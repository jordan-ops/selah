pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// Game mode — one flag that quiets everything while you game:
//   - Do-Not-Disturb goes on (previous state restored on disable)
//   - quickshell's animations stop (Motion.motionOn gates on this flag)
//   - Hyprland's animations/blur/shadows die, gaps and rounding go to 0,
//     border thins to 1 — one hl.config() eval.
// Restore is CAPTURE-AND-REPLAY: enable first reads all seven options
// with `hyprctl getoption`, disable feeds their exact values back
// through the same eval. Never `hyprctl reload` (that reapplies config
// files this shell doesn't own the state of — uncommitted edits, runtime
// tweaks — just to undo seven options) and never `hyprctl keyword`
// (this Hyprland runs the non-legacy Lua parser and answers
// "keyword can't work with non-legacy parsers. Use eval.").
//
// Optional auto rules: settings.json "gamemode.classes": ["steam", ...]
// (lowercase window classes). While that list is non-empty a 2 s poll
// watches the focused window: entering a match ENABLES game mode,
// leaving it DISABLES again — transition-based, so manual toggles win:
// enabling by hand is sticky, and turning it off mid-game won't re-arm
// until focus leaves the window and comes back.
Singleton {
    id: root

    property bool enabled: false
    property bool byRule: false    // armed by the class poll (auto-releases)
    property bool prevDnd: false   // DoNotDisturb state before we took it
    property bool wasMatched: false
    property var saved: null       // [[path, luaLiteral], ...] pre-enable

    readonly property var classes: {
        const v = Settings.values["gamemode.classes"]
        return (Array.isArray(v) ? v : [])
            .map(x => String(x).trim().toLowerCase()).filter(x => x !== "")
    }

    // every option below was probed with `hyprctl getoption` on this
    // machine first — all seven exist on the shipped Hyprland, and the
    // values are LUA SOURCE so configExpr() can emit them verbatim
    // (bools as true/false like appearance.lua writes them, gaps as the
    // scalars user-settings.lua writes them as).
    readonly property var tweaks: ({
        "animations:enabled": "false",
        "decoration:blur:enabled": "false",
        "decoration:shadow:enabled": "false",
        "general:gaps_in": "0",
        "general:gaps_out": "0",
        "general:border_size": "1",
        "decoration:rounding": "0"
    })

    // getoption prints "<type>: <value>" then "set: true/false"; the
    // typed line becomes a lua literal:
    //   bool: true            -> true
    //   int: 2                -> 2
    //   css gap data: 4 4 4 4 -> 4   (config sets gaps as scalars, so
    //                                 the first token is the whole value)
    // null = something this machine has never printed before — refuse to
    // guess and leave hyprland untouched instead of restoring garbage.
    function luaLiteral(line) {
        if (line.startsWith("bool: ")) {
            const v = line.slice(6).trim()
            return (v === "true" || v === "false") ? v : null
        }
        if (line.startsWith("int: ")) {
            const n = Number(line.slice(5).trim())
            return isNaN(n) ? null : String(n)
        }
        if (line.startsWith("css gap data: ")) {
            const n = Number(line.slice(14).trim().split(/\s+/)[0])
            return isNaN(n) ? null : String(n)
        }
        return null
    }

    // dotted config paths + lua literals -> one hl.config({ ... }) call,
    // same shape as this repo's own config/hypr/appearance.lua. Every
    // tweaks key is a bare lua identifier (animations, gaps_in,
    // border_size, …) so no quoting is needed anywhere.
    function configExpr(pairs) {
        const rootObj = {}
        for (let i = 0; i < pairs.length; i++) {
            const parts = pairs[i][0].split(":")
            let o = rootObj
            for (let j = 0; j < parts.length - 1; j++) {
                if (typeof o[parts[j]] !== "object") o[parts[j]] = {}
                o = o[parts[j]]
            }
            o[parts[parts.length - 1]] = pairs[i][1]
        }
        function ser(o) {
            let s = "{ "
            for (const k in o) {
                const v = o[k]
                s += k + " = " + (typeof v === "string" ? v : ser(v)) + ", "
            }
            return s + " }"
        }
        return "hl.config(" + ser(rootObj) + ")"
    }

    function push(pairs) {
        evalProc.command = ["hyprctl", "eval", configExpr(pairs)]
        evalProc.running = false
        evalProc.running = true
    }

    function enable(rule) {
        if (enabled) return
        prevDnd = DoNotDisturb.enabled
        DoNotDisturb.enabled = true
        byRule = rule
        saved = null
        enabled = true
        // one bash, sequential — output order matches Object.keys order
        captureProc.command = ["bash", "-c",
            Object.keys(tweaks).map(o => "hyprctl getoption " + o).join(" ; ")]
        captureProc.running = false
        captureProc.running = true
    }

    function disable() {
        if (!enabled) return
        enabled = false
        byRule = false
        if (!prevDnd) DoNotDisturb.enabled = false
        captureProc.running = false
        if (saved !== null) push(saved)
        saved = null
    }

    function toggle() { enabled ? disable() : enable(false) }

    // called by the focus poll below
    function evaluateFocus(cls) {
        const matched = cls !== "" && classes.includes(cls)
        if (matched && !wasMatched) enable(true)
        else if (!matched && wasMatched && enabled && byRule) disable()
        wasMatched = matched
    }

    Process {
        id: captureProc
        stdout: StdioCollector {
            onStreamFinished: {
                // a disable landed while this read was in flight — the
                // captured state is moot and must not be applied
                if (!root.enabled) return
                const lines = text.split("\n").map(l => l.trim())
                    .filter(l => l !== "" && !l.startsWith("set:"))
                const keys = Object.keys(root.tweaks)
                if (lines.length !== keys.length) {
                    console.log("[gamemode] unexpected getoption output:",
                        lines.length, "lines for", keys.length, "options —",
                        "leaving hyprland untouched")
                    return
                }
                const lits = lines.map(l => root.luaLiteral(l))
                if (lits.some(v => v === null)) {
                    console.log("[gamemode] unparsable getoption line —",
                        "leaving hyprland untouched")
                    return
                }
                root.saved = keys.map((k, i) => [k, lits[i]])
                root.push(keys.map(k => [k, root.tweaks[k]]))
            }
        }
    }
    Process {
        id: evalProc
        // hl.config prints nothing on success; anything here is a lua
        // error (bad path, wrong type) and should be visible in the log
        stderr: StdioCollector {
            onStreamFinished: {
                const e = text.trim()
                if (e !== "") console.log("[gamemode] hyprctl eval:", e)
            }
        }
    }

    // focus poll — only exists while auto rules are configured
    Timer {
        interval: 2000
        repeat: true
        running: root.classes.length > 0
        onTriggered: focusProc.running = true
    }
    Process {
        id: focusProc
        command: ["bash", "-c",
                  "hyprctl activewindow 2>/dev/null | sed -n 's/^class: //p' | head -n 1"]
        stdout: StdioCollector {
            onStreamFinished: root.evaluateFocus(text.trim().toLowerCase())
        }
    }

    IpcHandler {
        target: "gamemode"
        function toggle(): void { root.toggle() }
        function enable(): void { root.enable(false) }
        function disable(): void { root.disable() }
        function status(): bool { return root.enabled }
    }
}
