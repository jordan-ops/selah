pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Owner of the settings window's open state — the window chrome itself
// lives in Bar.qml like every other popup, pages and entries come from
// SettingsCatalog. The future "settings app" the bar revamp reserved a
// key for is this: a window over settings.json + the same qs ipc calls
// the hypr binds already use.
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

    property string page: "bar"
    property string focusId: ""   // launcher deep-link: row to highlight

    function show(page, focusId) {
        root.page = page && page !== "" ? page : "bar"
        root.focusId = focusId || ""
        open = true
    }

    function toggle() { open = !open }
    function hide() { open = false }

    IpcHandler {
        target: "settingsapp"
        function toggle(): void { root.toggle() }
        function show(page: string): void { root.show(page, "") }
        function showAt(page: string, focusId: string): void { root.show(page, focusId) }
        function hide(): void { root.hide() }
        function status(): bool { return root.open }
        // Apply / Revert over IPC too — same verbs as the window buttons,
        // usable from scripts: qs ipc call settingsapp apply
        function apply(): void { root.applyPending() }
        function revert(): void { root.revertPending() }
        function pending(): int { return root.pendingCount }
        // Hyprland reload for surfaces that read the config files instead
        // of live evals (the shell's glass / qs-glass layer rule) — same
        // safe path the keybind editor uses: persisted + pending values
        // are re-applied right after, so an un-Applied tweak never
        // silently reverts behind the user's back.
        function reload(): void { root.reloadHypr() }
    }

    // hyprswitch rows record their last flip under persistKey; hyprctl
    // eval is runtime-only, so re-apply those values once after session
    // start — otherwise the compositor comes back holding the Lua
    // defaults. One eval: a chunk takes many statements (newline join).
    Process { id: reapplyProc }

    Timer {
        id: reapplyTimer
        interval: 1500   // let hyprctl + settings.json settle at start
        onTriggered: root.reapplyPersisted()
    }
    Component.onCompleted: {
        reapplyTimer.start()
        animRead.running = true
    }

    function reapplyPersisted() {
        const script = root.buildReapplyScript()
        if (script === "") return
        reapplyProc.command = ["hyprctl", "eval", script]
        reapplyProc.running = true
    }

    // persisted hypr-side values as one eval chunk (shared by the
    // session-start reapply and the post-reload restore below) — any
    // entry carrying both keys: hyprswitch rows and the anim card alike
    function buildReapplyScript() {
        let script = ""
        const list = SettingsCatalog.entries
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            if (!e.persistKey || !e.hyprKey) continue
            const v = Settings.get(e.persistKey, null)
            if (v === null || v === undefined) continue
            // bool flips store true/false, numeric rows (scroll speed)
            // store their number — coerce only the string forms json
            // may hand back, pass everything else through as-is
            const val = v === "true" ? true : v === "false" ? false : v
            const keys = e.hyprKeys || [e.hyprKey]
            for (let k = 0; k < keys.length; k++)
                script += SettingsCatalog.hyprEval(keys[k],
                    SettingsCatalog.hyprLuaValue(val)) + "\n"
        }
        return script
    }

    // ——————— Hyprland animation speed (settings.json hypr.speedScale) ———————
    // appearance.lua is the read-only source of truth: parse its
    // hl.animation speeds and hl.curve spring params once, then eval the
    // whole set scaled as one chunk. speed is ds (higher = slower) so
    // speeds divide by the scale; springs mirror appearance.lua's own
    // retune — stiffness ×scale², dampening ×scale keeps every ζ (the
    // same math, reversed). 1× re-emits the base set verbatim, so
    // coming back to 1× restores it without a reload. Re-parsed and
    // re-applied after every reload through animRead — which covers
    // theme switches (switch-theme.sh runs hyprctl reload) and keybind
    // saves (reloadProc below).
    property real animScale: {
        const v = Settings.values["hypr.speedScale"]
        const n = v === undefined ? 1 : Number(v)
        // 0.5–1.5: the harness-proven band (2× inflates spring overshoot)
        return isNaN(n) ? 1 : Math.max(0.5, Math.min(1.5, n))
    }
    property var animLeaves: []
    property var animSprings: []
    property bool animBaseReady: false
    onAnimScaleChanged: animApply()

    Process {
        id: animRead
        command: ["cat", Quickshell.env("HOME") + "/.config/hypr/appearance.lua"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.animParse(text)
                root.animBaseReady = true
                root.animApply()
            }
        }
    }
    Process { id: animWrite }   // scaled hl.animation / hl.curve chunk

    function animParse(src) {
        const leaves = []
        const springs = []
        const lines = String(src).split("\n")
        for (let i = 0; i < lines.length; i++) {
            const ln = lines[i]
            if (ln.indexOf("hl.animation(") === 0) {
                const lf = ln.match(/leaf = "([^"]+)"/)
                const sp = ln.match(/speed = ([\d.]+)/)
                if (!lf || !sp) continue
                const en = ln.match(/enabled = (true|false)/)
                const bz = ln.match(/bezier = "([^"]+)"/)
                const sr = ln.match(/spring = "([^"]+)"/)
                const st = ln.match(/style = "([^"]+)"/)
                leaves.push({ leaf: lf[1], speed: parseFloat(sp[1]),
                              enabled: en ? en[1] : "true",
                              bezier: bz ? bz[1] : "", spring: sr ? sr[1] : "",
                              style: st ? st[1] : "" })
            } else if (ln.indexOf("hl.curve(") === 0
                       && ln.indexOf('type = "spring"') >= 0) {
                const nm = ln.match(/hl\.curve\("([^"]+)"/)
                const ki = ln.match(/stiffness = ([\d.]+)/)
                const ci = ln.match(/dampening = ([\d.]+)/)
                const ma = ln.match(/mass = ([\d.]+)/)
                if (!nm || !ki || !ci) continue
                springs.push({ name: nm[1], mass: ma ? parseFloat(ma[1]) : 1,
                               k: parseFloat(ki[1]), c: parseFloat(ci[1]) })
            }
        }
        root.animLeaves = leaves
        root.animSprings = springs
    }

    function animApply() {
        if (!root.animBaseReady) return
        const s = root.animScale
        let script = ""
        for (let i = 0; i < root.animLeaves.length; i++) {
            const L = root.animLeaves[i]
            const curve = L.bezier !== ""
                ? 'bezier = "' + L.bezier + '"' : 'spring = "' + L.spring + '"'
            script += 'hl.animation({ leaf = "' + L.leaf + '", enabled = ' + L.enabled
                + ', speed = ' + (L.speed / s).toFixed(2) + ', ' + curve
                + (L.style !== "" ? ', style = "' + L.style + '"' : "")
                + ' })\n'
        }
        for (let i = 0; i < root.animSprings.length; i++) {
            const S = root.animSprings[i]
            script += 'hl.curve("' + S.name + '", { type = "spring", mass = ' + S.mass
                + ', stiffness = ' + (S.k * s * s).toFixed(2)
                + ', dampening = ' + (S.c * s).toFixed(2) + ' })\n'
        }
        if (script === "") return
        animWrite.command = ["hyprctl", "eval", script]
        animWrite.running = true
    }

    // switch-theme.sh ends in a backgrounded hyprctl reload — eval'd
    // state (scaled speeds/springs, persisted toggles like
    // animations:enabled) drops back to appearance.lua / user-settings.lua
    // then. colors.json lands before that reload finishes, so debounce
    // the restore past it: one pass re-emits the scaled speed set AND
    // the persisted hypr toggles.
    Timer {
        id: animRestoreTimer
        interval: 900
        onTriggered: {
            if (root.animBaseReady) root.animApply()
            root.reapplyPersisted()
        }
    }
    Connections {
        target: Colors
        function onAccentChanged() { animRestoreTimer.restart() }
    }

    // The keybinding editor rewrites ~/.config/hypr/binds.lua and needs a
    // reload to take effect. hyprctl reload re-reads user-settings.lua
    // but drops live-only evals — so re-apply the persisted values AND
    // the still-pending set right after, or an un-Applied tweak would
    // silently revert behind the user's back.
    function reloadHypr() {
        reloadProc.command = ["hyprctl", "reload"]
        reloadProc.running = true
    }

    Process {
        id: reloadProc
        onExited: {
            let script = root.buildReapplyScript()
            const keys = Object.keys(root.hyprPending)
            for (let i = 0; i < keys.length; i++)
                script += SettingsCatalog.hyprEval(keys[i],
                    SettingsCatalog.hyprLuaValue(root.hyprPending[keys[i]])) + "\n"
            if (script !== "") {
                reapplyProc.command = ["hyprctl", "eval", script]
                reapplyProc.running = true
            }
            // appearance.lua may have changed with this reload — re-read
            // the base speeds/springs, which re-applies the scale too
            animRead.running = true
        }
    }

    // ——————— Apply / Revert ———————
    // hyprctl eval is runtime-only: slider / hyprKey-button / hyprswitch
    // rows take effect live but would be gone after a reload. Every such
    // commit is recorded here as PENDING against the value it had BEFORE
    // the first change (hyprBaseline). Apply writes the pending set into
    // ~/.config/hypr/user-settings.lua — hyprland.lua require()s that
    // file LAST (deep-merge, probe-verified in colors.lua), so the values
    // survive hyprctl reload and session restarts. Revert evals the
    // baselines back live and drops the record. settings.json rows
    // (switch/choice) and theme/wallpaper state persist on their own.
    property var hyprPending: ({})    // hyprKey -> latest live value
    property var hyprBaseline: ({})   // hyprKey -> value before this change
    // Non-hyprland pending values (the text-size row): hyprPending goes
    // into user-settings.lua, these re-run their own script instead —
    // same baseline dance, same Apply/Revert buttons, same dirty flag.
    property var extPending: ({})     // extKey -> latest live value
    property var extBaseline: ({})    // extKey -> value before this change
    readonly property int pendingCount: Object.keys(hyprPending).length
        + Object.keys(extPending).length
    readonly property bool dirty: pendingCount > 0

    // fired when extScript finished restoring a value (Revert) so the
    // owning row can re-read what actually landed
    signal extRestored()
    // fired when revertProc finished evaling hypr baselines back — every
    // hypr-reading row re-reads getoption, else its handle keeps showing
    // the value that was just reverted away
    signal revertDone()

    function hyprChanged(key, oldV, newV) {
        if (!key || oldV === null || oldV === undefined) return
        const pending = Object.assign({}, root.hyprPending)
        const base = Object.assign({}, root.hyprBaseline)
        if (!(key in base)) {                      // first change of this key
            if (String(oldV) === String(newV)) return
            base[key] = oldV
        }
        if (String(base[key]) === String(newV)) {  // dragged back to baseline
            delete base[key]
            delete pending[key]
        } else {
            pending[key] = newV
        }
        root.hyprBaseline = base
        root.hyprPending = pending
    }

    // SettingsTextSizeRow.commit mirror: register a non-hyprland change
    function extChanged(key, oldV, newV) {
        if (!key || oldV === null || oldV === undefined) return
        const pending = Object.assign({}, root.extPending)
        const base = Object.assign({}, root.extBaseline)
        if (!(key in base)) {
            if (String(oldV) === String(newV)) return
            base[key] = oldV
        }
        if (String(base[key]) === String(newV)) {
            delete base[key]
            delete pending[key]
        } else {
            pending[key] = newV
        }
        root.extBaseline = base
        root.extPending = pending
    }

    // JS value -> Lua literal: nested objects as tables, bools/numbers
    // verbatim, strings double-quoted (same shapes hyprEval emits).
    function luaLit(v, ind) {
        if (v !== null && typeof v === "object") {
            const keys = Object.keys(v)
            let pad0 = ""
            let pad = ""
            for (let i = 0; i < ind; i++) pad0 += "    "
            pad = pad0 + "    "
            if (keys.length === 0) return "{ }"
            let inner = ""
            for (let i = 0; i < keys.length; i++)
                inner += pad + keys[i] + " = " + luaLit(v[keys[i]], ind + 1) + ",\n"
            return "{\n" + inner + pad0 + "}"
        }
        if (typeof v === "boolean") return v ? "true" : "false"
        if (typeof v === "number") return String(v)
        return JSON.stringify(String(v))
    }

    function applyPending() {
        if (!root.dirty) return
        // non-hyprland values first: re-run their script (idempotent — it
        // already ran live on commit; this is the belt-and-braces "keep"
        // step the Apply button promises) and drop them from the record
        const ekeys = Object.keys(root.extPending)
        for (let i = 0; i < ekeys.length; i++) {
            if (ekeys[i] === "textSize") {
                extScript.command = [Quickshell.shellDir + "/scripts/set-text-size.sh",
                                     String(root.extPending[ekeys[i]])]
                extScript.running = true
            }
        }
        root.extPending = ({})
        root.extBaseline = ({})
        // nest "general:gaps_out" into { general: { gaps_out: v } }
        const groups = {}
        const keys = Object.keys(root.hyprPending)
        if (keys.length === 0) return   // ext-only pending: no lua to write
        for (let i = 0; i < keys.length; i++) {
            const parts = keys[i].split(":")
            if (groups[parts[0]] === undefined) groups[parts[0]] = {}
            let node = groups[parts[0]]
            for (let j = 1; j < parts.length - 1; j++) {
                if (node[parts[j]] === undefined) node[parts[j]] = {}
                node = node[parts[j]]
            }
            node[parts[parts.length - 1]] = root.hyprPending[keys[i]]
        }
        const content =
            "-- user-settings.lua — GENERATED by quickshell's settings app (Apply).\n" +
            "-- Hand edits are overwritten by the next Apply; hyprland.lua\n" +
            "-- require()s this file last, so these override the defaults above.\n" +
            "hl.config(" + luaLit(groups, 0) + ")\n"
        const path = Quickshell.env("HOME") + "/.config/hypr/user-settings.lua"
        // write to .tmp, luac-check when available, then move into place —
        // a half-written config must never reach hyprland's require()
        writeProc.command = ["bash", "-c",
            'printf %s "$1" > "$2.tmp" && ' +
            '{ ! command -v luac >/dev/null 2>&1 || luac -p "$2.tmp"; } && ' +
            'mv "$2.tmp" "$2"', "qs", content, path]
        writeProc.running = true
        root.hyprPending = ({})
        root.hyprBaseline = ({})
    }

    function revertPending() {
        if (!root.dirty) return
        // non-hyprland values: re-run their script with the baseline —
        // extRestored fires when it lands so the row re-reads
        const ekeys = Object.keys(root.extBaseline)
        for (let i = 0; i < ekeys.length; i++) {
            if (ekeys[i] === "textSize") {
                extScript.command = [Quickshell.shellDir + "/scripts/set-text-size.sh",
                                     String(root.extBaseline[ekeys[i]])]
                extScript.running = true
            }
        }
        root.extPending = ({})
        root.extBaseline = ({})
        let script = ""
        const keys = Object.keys(root.hyprBaseline)
        for (let i = 0; i < keys.length; i++)
            script += SettingsCatalog.hyprEval(keys[i],
                SettingsCatalog.hyprLuaValue(root.hyprBaseline[keys[i]])) + "\n"
        if (keys.length > 0) {
            revertProc.command = ["hyprctl", "eval", script]
            revertProc.running = true
        }
        // hypr-side rows that also wrote settings.json on flip — put the
        // old value back, or the start-of-session reapply would resurrect
        // what the user just reverted
        const list = SettingsCatalog.entries
        for (let i = 0; i < list.length; i++) {
            const e = list[i]
            if (!e.persistKey || !e.hyprKey) continue
            if (e.hyprKey in root.hyprBaseline)
                Settings.set(e.persistKey, root.hyprBaseline[e.hyprKey])
        }
        root.hyprPending = ({})
        root.hyprBaseline = ({})
    }

    Process { id: writeProc }   // user-settings.lua writer
    Process {
        id: revertProc          // baseline re-eval → rows re-read on exit
        onExited: root.revertDone()
    }
    // runner for non-hyprland scripts (text size) — exits signal the
    // owning row to re-read, and any script complaint lands in the log
    Process {
        id: extScript
        stderr: StdioCollector {
            onStreamFinished: if (text.trim() !== "")
                console.log("SettingsApp: set-text-size:", text.trim())
        }
        onExited: root.extRestored()
    }
}
