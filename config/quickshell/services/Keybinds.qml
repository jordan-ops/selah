// Parser/overlay adapted from Nebula shell (GPL-3.0)
pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Keybind cheat sheet service — parses ~/.config/hypr/binds.lua (the file
// hyprland actually loads; same reasoning Nebula documents for parsing lua
// instead of the .conf chain) into [{ name, binds: [{ chord, desc }] }]
// grouped by binds.lua's `---- NAME ----` section headers, and owns the
// overlay's `open` flag. CheatSheet.qml draws it.
//
// The statement/eval logic is adapted from SettingsKeybindsEditor.qml and
// kept separate deliberately: that file's parser DEPTH-SKIPS `for` bodies
// (a generated chord only exists at runtime, so the editor can't write it),
// while this service must surface those loop-generated binds as a range —
// the two need different behavior and neither file should be bent for the
// other. SettingsKeybindsEditor stays untouched.
//
// IPC: qs ipc call cheatsheet toggle / open / close
Singleton {
    id: root

    property bool open: false
    // Multi-monitor bookkeeping, same as Clipboard/Aether: every screen has
    // a window (CheatSheet.qml's Variants) but only the screen that was
    // focused when this opened renders — otherwise several surfaces claim
    // WlrKeyboardFocus.Exclusive at once and they fight over the keys.
    property string ownerScreen: ""
    onOpenChanged: {
        if (!open) return
        const fm = Hyprland.focusedMonitor
        ownerScreen = fm ? fm.name
            : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
    }

    readonly property string path:
        Quickshell.env("HOME") + "/.config/hypr/binds.lua"

    // [{ name, binds: [{ chord, desc }] }] — sections whose binds are all
    // commented out are dropped by parse()
    property var groups: []

    readonly property int bindCount: {
        var n = 0
        for (var i = 0; i < root.groups.length; i++)
            n += root.groups[i].binds.length
        return n
    }

    function openSheet() {
        // Bar.qml hands WlrKeyboardFocus.Exclusive to these surfaces — two
        // claiming it at once fight and neither wins (the comment Aether's
        // openPicker makes about the same problem), so retire them first.
        Launcher.closeLauncher()
        Themes.closePicker()
        Wallpapers.closePicker()
        Clipboard.close()
        ControlCenter.close()
        ClockCard.close()
        Aether.closePicker()
        PowerMenu.open = false
        open = true
    }

    function close() { open = false }
    function toggle() { open ? close() : openSheet() }

    // live file: the settings keybinds editor writes this file, so edits
    // (add/remove/disable) show up in the cheat sheet without a restart
    FileView {
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.groups = root.parse(text())
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void { root.toggle() }
        function open(): void { root.openSheet() }
        function close(): void { root.close() }
    }

    // ——————— lua helpers ———————

    // Split `s` on `delim` only where it sits outside quotes and outside
    // (){} nesting. Lua's concat ".." and its comment "--" both occur inside
    // string literals in this config, so naive splitting mangles them.
    // (Nebula's _splitTop + SettingsKeybindsEditor's splitConcat, merged:
    // index-accurate output, both quote styles.)
    function splitTop(s, delim) {
        const out = []
        let cur = "", depth = 0, q = ""
        for (let i = 0; i < s.length; i++) {
            const c = s[i]
            if (q) {
                cur += c
                if (c === "\\" && i + 1 < s.length) { cur += s[++i]; continue }
                if (c === q) q = ""
                continue
            }
            if (c === '"' || c === "'") { q = c; cur += c; continue }
            if (c === "(" || c === "{") { depth++; cur += c; continue }
            if (c === ")" || c === "}") { depth--; cur += c; continue }
            if (depth === 0 && s.substr(i, delim.length) === delim) {
                out.push(cur)
                cur = ""
                i += delim.length - 1
                continue
            }
            cur += c
        }
        out.push(cur)
        return out
    }

    // mainMod .. " + W"  →  "SUPER + W". String literals resolve, `local`
    // string locals resolve through the map, bare identifiers (loop vars,
    // `terminal` and friends) stay verbatim; a genuinely complex expression
    // → null, so the caller skips that row instead of showing nonsense.
    function evalChord(expr, locals) {
        const parts = splitTop(String(expr), "..")
        let out = ""
        for (let i = 0; i < parts.length; i++) {
            const t = parts[i].trim()
            if (t === "") continue
            if (t[0] === '"' || t[0] === "'") {
                const q = t[0]
                let s = t.slice(1)
                if (s.length > 0 && s[s.length - 1] === q) s = s.slice(0, -1)
                out += s.replace(/\\(.)/g, "$1")
            } else if (locals.hasOwnProperty(t)) out += locals[t]
            else if (/^[A-Za-z_]\w*$/.test(t)) out += t
            else return null
        }
        const chord = out.trim()
        return chord === "" ? null : chord
    }

    // Same resolution, lenient: used for descriptions, where an unresolved
    // identifier is printed verbatim rather than failing the row
    // (Nebula's _resolveExpr).
    function resolveExpr(expr, locals) {
        const parts = splitTop(String(expr), "..")
        let out = ""
        for (let i = 0; i < parts.length; i++) {
            const t = parts[i].trim()
            if (t === "") continue
            if (t[0] === '"' || t[0] === "'") {
                const q = t[0]
                let s = t.slice(1)
                if (s.length > 0 && s[s.length - 1] === q) s = s.slice(0, -1)
                out += s.replace(/\\(.)/g, "$1")
            } else if (locals.hasOwnProperty(t)) out += locals[t]
            else out += t
        }
        return out.trim()
    }

    // first `--` outside quotes — the trailing description comment
    function findComment(s, from) {
        let q = ""
        for (let i = from; i < s.length; i++) {
            const c = s[i]
            if (q) {
                if (c === "\\") { i++; continue }
                if (c === q) q = ""
                continue
            }
            if (c === '"' || c === "'") { q = c; continue }
            if (c === "-" && s[i + 1] === "-") return i
        }
        return -1
    }

    // "window-fullscreen" style names → "Window fullscreen" (Nebula)
    function humanize(s) {
        if (!s) return ""
        let out = String(s).replace(/([a-z0-9])([A-Z])/g, "$1 $2")
            .replace(/[_\-]+/g, " ")
        out = out.trim().toLowerCase()
        return out.charAt(0).toUpperCase() + out.slice(1)
    }

    // No comment on the statement → read the dispatcher call itself, the
    // way Nebula's _describe does: exec_cmd shows the command, hl.dsp.foo()
    // shows "Foo — key value".
    function describe(action, locals) {
        const d = String(action).trim()

        const e = d.match(/exec_cmd\s*\(([\s\S]*)\)\s*$/)
        if (e) return resolveExpr(e[1], locals)

        const m = d.match(/hl\.dsp\.([A-Za-z_.]+)\s*\(([\s\S]*)\)\s*$/)
        if (m) {
            const name = humanize(m[1].replace(/\./g, " "))
            const inner = m[2].trim()
            if (inner === "" || inner === "{}") return name
            const kv = inner.match(/([A-Za-z_]+)\s*=\s*"?([^",}]+)"?/)
            if (kv) return name + " — " + kv[1] + " " + kv[2].trim()
            const lit = inner.match(/^"([^"]*)"$/)
            if (lit) return name + " — " + lit[1]
            return name
        }
        return d
    }

    // One hl.bind statement spanning lines[start…]: balance parens across
    // lines (quotes + escapes respected), bail out on a blank line inside
    // the statement. Returns { end, raw } — adapted from
    // SettingsKeybindsEditor.statementAt(), minus its disabled-bind branch
    // (a `-- hl.bind(` line never matches parse()'s active-statement test,
    // so commented-out binds are skipped rather than listed).
    function statementSpan(lines, start) {
        let d = 0, q = "", started = false, end = -1
        for (let j = start; j < lines.length && end < 0; j++) {
            const ln = lines[j]
            for (let k = 0; k < ln.length; k++) {
                const c = ln[k]
                if (q) {
                    if (c === "\\") { k++; continue }
                    if (c === q) q = ""
                    continue
                }
                if (c === '"' || c === "'") { q = c; continue }
                if (c === "(") { d++; started = true }
                else if (c === ")") {
                    d--
                    if (started && d === 0) { end = j; break }
                }
            }
            if (end < 0 && j > start && ln.trim() === "") return null
        }
        if (end < 0) return null
        return { end: end, raw: lines.slice(start, end + 1).join("\n") }
    }

    // Unpack one statement → { chord, desc } or null. The trailing `--`
    // comment wins as the description (binds.lua writes them for exactly
    // this); without one the dispatcher call is described as above.
    function bindFrom(raw, locals) {
        const bindIdx = raw.indexOf("hl.bind(")
        if (bindIdx < 0) return null

        let desc = "", code = raw
        const cmt = findComment(raw, bindIdx + 8)
        if (cmt >= 0) {
            desc = raw.slice(cmt).split("\n")[0].replace(/^--\s*/, "").trim()
            code = raw.slice(0, cmt)
        }
        code = code.replace(/\s+$/, "")
        if (code[code.length - 1] !== ")") return null

        // walk hl.bind( … to its matching close paren (string-aware)
        let d = 0, q = "", close = -1
        for (let k = bindIdx + 7; k < code.length; k++) {
            const c = code[k]
            if (q) {
                if (c === "\\") { k++; continue }
                if (c === q) q = ""
                continue
            }
            if (c === '"' || c === "'") { q = c; continue }
            if (c === "(") d++
            else if (c === ")") { d--; if (d === 0) { close = k; break } }
        }
        if (close < 0) return null

        // args[0] = chord, args[1] = dispatcher; a third options table
        // ({ mouse = true }) rides along in Nebula's split and is ignored
        const args = splitTop(code.slice(bindIdx + 8, close), ",")
        if (args.length < 2) return null

        const chord = evalChord(args[0], locals)
        if (chord === null) return null
        if (desc === "") desc = describe(args[1], locals)
        return { chord: chord, desc: desc }
    }

    // `key` / `i` → the loop's range ("1–10"), in the chord AND the
    // description (Nebula's loopRange behavior, plus `key`, which is this
    // file's alias for `i` inside `for i = 1, 10 do`). Takes the loop state
    // as arguments instead of closing over parse()'s locals — deliberately
    // not a helper declared INSIDE parse(): qmllint's analyzer silently
    // aborts (zero warnings, exit 0, all checks skipped) on a function
    // declaration nested in a function that uses const/let, which would
    // make this file pass lint unchecked.
    function loopSub(s, loopVar, loopRange, aliases) {
        if (loopRange === "") return s
        const names = [loopVar].concat(aliases).filter(n => n !== "")
        if (names.length === 0) return s
        const alt = names.map(n => n.replace(/[^\w]/g, "")).join("|")
        if (alt === "") return s
        return s.replace(new RegExp("\\b(?:" + alt + ")\\b"), loopRange)
    }

    function parse(text) {
        const src = String(text)
        const lines = src.split("\n")
        const locals = {}
        const groups = []
        let current = null
        let loopVar = "", loopRange = ""
        let loopAliases = []

        // `local mainMod = "SUPER"` normally sits above the first bind, but
        // pre-scan like SettingsKeybindsEditor so a rebound mainMod resolves
        // wherever it is declared
        const mm = src.match(/local\s+mainMod\s*=\s*"([^"]*)"/)
        if (mm) locals.mainMod = mm[1]

        let i = 0
        while (i < lines.length) {
            const line = lines[i].trim()
            if (line === "") { i++; continue }

            // local name = "value" → resolvable inside `..` expressions
            const loc = line.match(/^local\s+([A-Za-z_]\w*)\s*=\s*"([^"]*)"/)
            if (loc) { locals[loc[1]] = loc[2]; i++; continue }

            // ---- KEYBINDINGS ---- → a section. The pure-dash separator
            // lines around it match too, so a header must carry a name that
            // isn't just dashes (Nebula matched `-- ── Name ──` comments
            // instead; this file uses bare-dash banners).
            const sec = line.match(/^-{2,}\s*(.+?)\s*-{2,}$/)
            if (sec) {
                const name = sec[1].trim()
                if (name.replace(/-/g, "").trim() !== "") {
                    current = { name: name, binds: [] }
                    groups.push(current)
                }
                i++
                continue
            }

            // for i = 1, 10 do — the body binds ten keys, show the range
            const forM = line.match(/^for\s+([A-Za-z_]\w*)\s*=\s*(\d+)\s*,\s*(\d+)\s*do/)
            if (forM) {
                loopVar = forM[1]
                loopRange = forM[2] + "–" + forM[3]
                loopAliases = []
                i++
                continue
            }
            if (loopVar !== "" && /^end\b/.test(line)) {
                loopVar = ""
                loopRange = ""
                loopAliases = []
                i++
                continue
            }
            // `local key = i % 10` — the loop's alias for the counter
            if (loopVar !== "") {
                const al = line.match(/^local\s+([A-Za-z_]\w*)\s*=\s*([A-Za-z_]\w*)\s*%/)
                if (al && al[2] === loopVar) loopAliases.push(al[1])
            }

            // real binds only: comments, separators and loop plumbing fall
            // through here. `local x = hl.bind(...)` counts as a bind.
            if (!/^(?:local\s+[A-Za-z_]\w*\s*=\s*)?hl\.bind\(/.test(line)) {
                i++
                continue
            }

            const st = statementSpan(lines, i)
            if (!st) { i++; continue }
            const b = bindFrom(st.raw, locals)
            i = st.end + 1
            if (!b) continue

            // binds that arrive before any `---- NAME ----` banner group
            // under "General" (Nebula's fallback)
            if (!current) {
                current = { name: "General", binds: [] }
                groups.push(current)
            }
            current.binds.push({
                // Nebula tidies spacing around the separator so caps split
                // cleanly on " + "
                chord: loopSub(b.chord, loopVar, loopRange, loopAliases)
                    .replace(/\s*\+\s*/g, " + ").trim(),
                desc: loopSub(b.desc, loopVar, loopRange, loopAliases)
            })
        }

        return groups.filter(g => g.binds.length > 0)
    }
}
