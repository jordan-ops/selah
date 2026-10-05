pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

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
    property string query: ""
    property int selectedIndex: 0

    // typing rebuilds `results` — snap the selection back to the top so the
    // pill always has a row to land on (a stale index past the new result
    // count would leave nothing selected at all) and re-run the calculator
    // attempt for the new query
    onQueryChanged: {
        selectedIndex = 0
        maybeCalc(query.trim().toLowerCase())
    }

    // --- calculator --------------------------------------------------------
    // Math-shaped queries get an answer row on top (see results below).
    // Evaluation runs in scripts/calc.py — python3 AST whitelist, never
    // eval'd in QML. calcPending remembers which expression the running
    // process was asked for so a slow run can't post its answer under a
    // newer query.
    property string calcExpr: ""
    property string calcPending: ""
    property string calcValue: ""

    function looksMath(t) {
        if (t.length < 2 || t.length > 60) return false
        if (!/^[\d\s().+\-*/%^]+$/.test(t)) return false
        if (!/\d/.test(t)) return false
        // the operator must sit between two operands — "-5" alone is a
        // number, not a calculation, and must not spawn a calc row
        return /[\d)]\s*[-+*/%^]\s*[\d(]/.test(t)
    }

    function maybeCalc(t) {
        if (!looksMath(t)) {
            calcExpr = ""
            calcValue = ""
            if (calcProc.running) calcProc.running = false
            return
        }
        if (t === calcPending) return
        calcExpr = t
        calcValue = ""
        calcProc.running = false
        calcProc.command = ["python3", Quickshell.shellPath("scripts/calc.py"), t]
        calcPending = t
        calcProc.running = true
    }

    Process {
        id: calcProc
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim()
                if (v !== "" && root.calcPending === root.calcExpr)
                    root.calcValue = v
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0 && root.calcPending === root.calcExpr)
                root.calcValue = ""
        }
    }

    // --- emoji (":" mode) ---------------------------------------------------
    // assets/emoji.json is the [{ch, name, kw}] set adapted from Nebula
    // (GPL-3.0); FileView loads it once and re-reads it on change. Rows
    // carry `glyph` so the Bar delegate paints the character itself in
    // Noto Color Emoji instead of looking up an icon that doesn't exist.
    property var emoji: []
    FileView {
        path: Quickshell.shellPath("assets/emoji.json")
        watchChanges: true
        printErrors: false
        onLoaded: {
            try { root.emoji = JSON.parse(text()) }
            catch (e) { root.emoji = [] }
        }
        onFileChanged: reload()
    }

    // settings.json arrays — edit the file or drive it via
    // `qs ipc call settings set launcher.fav '["firefox"]'`
    function strList(key) {
        const v = Settings.values[key]
        return Array.isArray(v) ? v : []
    }

    // desktop ids (or display names) pinned to the top of app results
    function isFav(d) {
        const id = (d.id || "").toLowerCase()
        const nm = (d.name || "").toLowerCase()
        return strList("launcher.fav").some(x => {
            const s = String(x).trim().toLowerCase()
            return s !== "" && (s === id || s === nm)
        })
    }

    // desktop ids (or display names) that never appear at all
    function isHidden(d) {
        const id = (d.id || "").toLowerCase()
        const nm = (d.name || "").toLowerCase()
        return strList("launcher.hidden").some(x => {
            const s = String(x).trim().toLowerCase()
            return s !== "" && (s === id || s === nm)
        })
    }

    // deletion (model churn) can shrink the list under the selection just
    // as easily — keep the index inside the model so the pill always has a
    // row to land on
    onResultsChanged: {
        if (selectedIndex >= results.length)
            selectedIndex = Math.max(0, results.length - 1)
    }

    // --- delete-from-launcher (Delete key → confirm dialog) ------------
    property bool confirmDelete: false
    property int confirmChoice: 1     // 0 = yes, 1 = no; opens ON no so a
                                      // stray Enter can never delete
    property var confirmEntry: null   // frozen at request time: the dialog
                                      // must act on the row that opened it

    function selectedEntry() {
        if (results.length === 0) return null
        return results[Math.min(selectedIndex, results.length - 1)]
    }

    // Settings rows are not installed software — only DesktopEntry rows
    // carry an id (quickshell's desktop-file identity).
    function removable(e) {
        return e != null && typeof e.id === "string" && e.id !== ""
    }

    // both installer generations count as a web app: webapp-launch.sh
    // URLs and the omarchy tool's chromium --app= launchers
    function isWebapp(e) {
        const x = (e != null && e.execString) || ""
        return x.includes("webapp-launch.sh") || x.includes("--app=")
    }

    function requestDelete() {
        const e = selectedEntry()
        if (!removable(e)) return
        confirmEntry = e
        confirmChoice = 1
        confirmDelete = true
    }

    function confirmCancel() {
        confirmDelete = false
        confirmEntry = null
    }

    function confirmAccept() {
        if (!confirmDelete) return
        const e = confirmEntry
        const go = confirmChoice === 0 && removable(e)
        confirmDelete = false
        confirmEntry = null
        if (!go) return
        closeLauncher()
        // detached: the webapp branch finishes silently; the system branch
        // reopens itself under a floating foot (remove-app.sh explains why)
        Quickshell.execDetached([Quickshell.shellPath("scripts/remove-app.sh"), e.id])
    }

    function pageMeta(id) {
        return SettingsCatalog.pages.find(p => p.id === id)
            || { name: "Setting", icon: "preferences-system" }
    }

    // ">" scopes the search to the settings CATALOG ONLY — the catalog
    // used to sit above every app hit, which buried apps under settings
    // rows on every keystroke. Bare ">" browses the whole catalog (first
    // 20 rows); a plain query never shows settings at all anymore.
    readonly property var results: {
    const q = query.trim().toLowerCase()

    if (q.startsWith(">")) {
        const s = q.slice(1).trim()
        // searchable = entries without the section headings (page chrome)
        return SettingsCatalog.searchable.filter(e => {
            const hay = [e.label, e.description, e.keywords, pageMeta(e.page).name]
                .filter(Boolean).join(" ").toLowerCase()
            return s === "" || s.split(/\s+/).every(t => hay.includes(t))
        }).slice(0, s === "" ? 20 : 40).map(e => ({
            name: e.label,
            comment: pageMeta(e.page).name + " — " + (e.description || "Setting"),
            icon: pageMeta(e.page).icon,
            execute: () => SettingsApp.show(e.page, e.id)
        }))
    }

    // ":" scopes to the emoji list — substring match on name + keywords,
    // capped at 40 so the pill never runs away; Enter copies the character
    if (q.startsWith(":")) {
        const s = q.slice(1).trim()
        return root.emoji
            .filter(e => s === "" || (e.name + " " + (e.kw || "")).toLowerCase().includes(s))
            .slice(0, 40)
            .map(e => ({
                name: e.name,
                comment: e.ch,
                icon: "",
                glyph: e.ch,
                execute: () => Quickshell.execDetached(["wl-copy", e.ch])
            }))
    }

    // plain query → installed apps only (hidden filtered out, favourites
    // float to the top, then alphabetical)
    const apps = [...DesktopEntries.applications.values]
        .filter(d => d.name && !isHidden(d))
        .filter(d => {
            if (q === "") return true
            const name = (d.name || "").toLowerCase()
            const comment = (d.comment || "").toLowerCase()
            return name.includes(q) || comment.includes(q)
        })
        .sort((a, b) => (isFav(a) ? 0 : 1) - (isFav(b) ? 0 : 1)
            || a.name.localeCompare(b.name))
        .slice(0, q === "" ? 50 : 40)

    if (calcValue !== "" && calcExpr === q)
        return [{
            name: "= " + calcValue,
            comment: "calculated — Enter copies the answer",
            icon: "accessories-calculator",
            execute: () => Quickshell.execDetached(["wl-copy", calcValue])
        }, ...apps]

    return apps
}

    function openLauncher() {
        query = ""
        selectedIndex = 0
        confirmDelete = false
        confirmEntry = null
        open = true
    }

    function closeLauncher() {
        open = false
        query = ""
        // a close must never leave a stale dialog armed for the next open
        confirmDelete = false
        confirmEntry = null
    }

    function moveSelection(delta) {
        if (results.length === 0) return
        selectedIndex = (selectedIndex + delta + results.length) % results.length
    }

    // Terminal=true entries (cliamp, htop, ncmpcpp…): quickshell's
    // DesktopEntry.execute() runs the Exec line as-is, so a TUI starts
    // with no controlling tty and dies before drawing anything
    // ("bubbletea: could not open TTY" is cliamp's way of saying it).
    // Wrap those in foot instead — everything else keeps the built-in
    // execute() untouched.
    //
    // foot -T sets the window title up front because foot's class is
    // always just "foot": the only handle a window rule has on this is
    // the title (same reason rules.lua matches "Uninstall.*" by title).
    function launch(e) {
        if (e == null) return
        const inTerminal = e.runInTerminal === true
            && e.command && e.command.length > 0
        if (!inTerminal) {
            e.execute()
            return
        }
        const argv = ["foot", "-T", (e.name && e.name !== "") ? e.name : "foot"]
        if (e.workingDirectory)
            argv.push("--working-directory=" + e.workingDirectory)
        argv.push("-e")
        Quickshell.execDetached(argv.concat(e.command))
    }

    function launchSelected() {
        if (results.length === 0) return
        launch(results[Math.min(selectedIndex, results.length - 1)])
        closeLauncher()
    }

    IpcHandler {
        target: "launcher"
        function toggle(): void {
            if (root.open) root.closeLauncher()
            else root.openLauncher()
        }
        // same shape as tray count / clipboard count: how many apps the
        // launcher can actually SEE — hidden-listed ids don't count, so
        // it doubles as the check that a freshly created .desktop has
        // been picked up (it only changes on restart).
        function count(): string {
            return String(DesktopEntries.applications.values
                .filter(d => !root.isHidden(d)).length)
        }
        // prefill the search box from scripts/tests — opens the launcher
        // first so the results pill renders (set the text field too when
        // it exists, so field and results agree)
        function search(q: string): void {
            if (!root.open) root.openLauncher()
            root.query = q
        }
    }
}