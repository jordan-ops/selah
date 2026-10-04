pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Aether wallpaper + palette picker — state and subprocesses.
//
// The UI is modelled on aether's own desktop app (Wails/Svelte), scaled down
// to what an overlay can carry comfortably:
//
//   aether app                      this picker
//   ------------------------------   -------------------------------------
//   tab strip: Local/Wallhaven/...   view: Themes | Local | Wallhaven
//   flat local browser               Themes groups wallpapers BY THEME, so
//                                    the library is never one flat pile
//   WallhavenFilters (search +       same: search box + toplist/latest/
//     sorting select)                  random/... chips, inside the overlay
//   SettingsSidebar:                 left panel:
//     ExtractionModeSelect             23 extract modes in aether's 5 groups
//     PresetsSection                   38 static 16-colour presets
//     ColorAdjustments                 12 sliders (saturation, vibrance, ...)
//   ActionBar: Apply / Save as new   footer: Create / Create + apply
//
// Everything colour-related is delegated to the aether binary so the numbers
// are aether's, not ours:
//
//   --extract-palette <wp> --extract-mode <m>   -> 16 base colours      (~44 ms)
//   --adjust-palette  '<16>' --saturation 20 ... -> 16 edited colours   (~53 ms)
//   --show-variables   '<16>'                   -> every colors.toml key
//
// The last one is what lets a palette the user edited land as a real theme:
// it runs aether's own palette->role mapping (accent, bg shades, orange/brown)
// and returns exactly the keys aether's --generate writes, verified key-for-key.
// scripts/aether-apply.sh feeds the result to switch-theme.sh.
//
// Mirrors services/Wallpapers.qml: one shared `open` flag plus ownerScreen so
// only the focused screen's bar reacts. AetherPicker.qml does the drawing.
Singleton {
    id: root

    property bool open: false
    property string ownerScreen: ""

    onOpenChanged: {
        if (!open) return
        const fm = Hyprland.focusedMonitor
        ownerScreen = fm ? fm.name
            : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
    }

    readonly property string home: Quickshell.env("HOME")
    readonly property string wallpaperDir: home + "/Wallpapers"
    readonly property string applyScript:
        Quickshell.shellDir + "/scripts/aether-apply.sh"
    readonly property string listScript:
        Quickshell.shellDir + "/scripts/aether-list.py"
    readonly property string manageScript:
        Quickshell.shellDir + "/scripts/theme-manage.py"
    readonly property string dataDir: Quickshell.shellDir + "/aether-data"

    // ==================================================================
    // aether's own tables (modes / slider limits / presets), loaded from
    // aether-data/*.json — generated straight out of aether's frontend
    // constants so the lists can never drift from the app.
    // ==================================================================
    property var modeGroups: []
    property var modes: []
    property var limits: ({})
    property var presets: ({})
    property bool dataLoaded: false

    FileView {
        path: root.dataDir + "/modes.json"
        printErrors: false
        onLoaded: {
            try {
                const d = JSON.parse(text())
                root.modeGroups = d.groups || []
                root.modes = d.modes || []
                root._checkData()
            } catch (e) { console.warn("aether modes.json:", e) }
        }
    }
    FileView {
        path: root.dataDir + "/adjustments.json"
        printErrors: false
        onLoaded: {
            try { root.limits = JSON.parse(text()); root._checkData() }
            catch (e) { console.warn("aether adjustments.json:", e) }
        }
    }
    FileView {
        path: root.dataDir + "/presets.json"
        printErrors: false
        onLoaded: {
            try { root.presets = JSON.parse(text()); root._checkData() }
            catch (e) { console.warn("aether presets.json:", e) }
        }
    }
    function _checkData() {
        const ok = modes.length > 0 && Object.keys(limits).length > 0
                && Object.keys(presets).length > 0
        if (ok && !dataLoaded) {
            dataLoaded = true
            if (!adjustments || Object.keys(adjustments).length === 0)
                adjustments = defaultAdjustments()
        }
    }

    // ==================================================================
    // view state
    // ==================================================================
    // "themes" | "local" | "wallhaven"
    property string view: "themes"
    property bool groupOpen: false
    property string groupTheme: ""
    // non-empty: we are picking a wallpaper to ADD to this theme instead of
    // creating a new one. Set from the open group's "+ add" buttons.
    property string addTheme: ""

    property string filter: ""

    // ==================================================================
    // listings
    // ==================================================================
    property var groups: []        // [{name,dir,count,cover,wallpapers:[...]}]
    property var localItems: []    // standalone wallpapers only
    property bool listLoaded: false
    property string listError: ""
    property var viewModel: []     // what the grid draws (see rebuildModel)
    property int currentIndex: 0

    // ==================================================================
    // wallhaven
    // ==================================================================
    // Sorting labels mirror WallhavenFilters.svelte's select. aether's CLI
    // spells "latest" as date_added, which is also its default.
    readonly property var sortings: ([
        { id: "toplist",    label: "Toplist" },
        { id: "date_added", label: "Latest" },
        { id: "random",     label: "Random" },
        { id: "relevance",  label: "Relevance" },
        { id: "views",      label: "Views" },
        { id: "favorites",  label: "Favorites" }
    ])
    property var whItems: []
    property string whQuery: ""
    property string whSorting: "toplist"
    property int whPage: 1
    property int whLastPage: 1
    property int whTotal: 0
    property bool whSearching: false
    // true while the in-flight whSearchProc run should APPEND its page to
    // whItems instead of replacing them (infinite scroll). Set immediately
    // before running=true and consumed by the parse, so it always describes
    // the run that just finished.
    property bool whAppending: false
    property string whLoadedFor: ""   // "sorting|query" behind whItems

    // ==================================================================
    // palette
    // ==================================================================
    property string extractMode: "material"
    property bool lightMode: false
    property var basePalette: []      // 16 raw (extraction or preset)
    property var palette: []          // 16 shown + used to create the theme
    property string paletteSource: "" // path basePalette came from
    property bool presetActive: false
    property string presetName: ""
    property var adjustments: ({})

    property bool extracting: false
    property bool adjusting: false
    property bool applying: false
    property string statusMsg: ""
    property bool createWithApply: true

    // Rapid arrow-key scrolling fires extracts faster than they finish. Only
    // the LAST requested path matters, so park it and drain when the running
    // one exits — otherwise the preview lags behind the selection.
    property string pendingExtractPath: ""
    property bool pendingExtractLightMode: false
    property int pendingExtractSession: 0
    property int sessionId: 0

    property var paletteCache: ({})   // "mode|light|path" -> [16]
    property var adjustCache: ({})    // "base|adjKey"     -> [16]

    readonly property bool busy: extracting || adjusting || applying
    readonly property bool canCreate: selectedWallpaper() !== null
                                      && palette.length === 16 && !busy

    // Wallpaper paths are user files: a space or "#" in a name would truncate
    // the URL at that byte. Same helper LockScreen.qml uses. wallhaven cards
    // already carry an http(s) URL, which needs no prefixing.
    function fileUrl(path) {
        if (!path) return ""
        const s = String(path)
        if (s.startsWith("http://") || s.startsWith("https://")) return s
        return "file://" + s.split("/").map(encodeURIComponent).join("/")
    }

    function defaultAdjustments() {
        const out = {}
        for (const k in limits) out[k] = limits[k].default
        return out
    }

    // ==================================================================
    // session
    // ==================================================================
    function openPicker() {
        // Bar.qml hands WlrKeyboardFocus.Exclusive to Launcher/Themes/
        // Wallpapers/Clipboard. Two surfaces claiming it at once fight over
        // the keyboard and neither wins, so retire those first.
        Launcher.closeLauncher()
        Themes.closePicker()
        Wallpapers.closePicker()
        Clipboard.close()
        beginSession()
        open = true
    }

    function closePicker() { open = false }
    function toggle() { open ? closePicker() : openPicker() }
    function dismiss() { closePicker() }

    function beginSession() {
        sessionId++
        filter = ""
        pendingExtractPath = ""
        applying = applyProc.running || whDownloadProc.running
        extracting = extractProc.running
        statusMsg = applying ? "Finishing previous apply ..." : ""
        listLoaded = false
        refresh()
        if (view === "wallhaven" && whItems.length === 0)
            whSearchTimer.restart()
    }

    function refresh() { if (!listProc.running) listProc.running = true }

    // ==================================================================
    // navigation between the three views / groups
    // ==================================================================
    function setView(v) {
        if (v === view) return
        view = v
        filter = ""
        groupOpen = false
        addTheme = ""
        currentIndex = 0
        if (v === "wallhaven" && whItems.length === 0) whSearchTimer.restart()
        rebuildModel()
        Qt.callLater(extractTimer.restart)
    }

    function openGroup(name) {
        view = "themes"
        filter = ""
        groupTheme = name
        groupOpen = true
        currentIndex = 0
        rebuildModel()
        Qt.callLater(extractTimer.restart)
    }

    function closeGroup() {
        groupOpen = false
        filter = ""
        currentIndex = 0
        rebuildModel()
        Qt.callLater(extractTimer.restart)
    }

    // "+ add wallpaper to <theme>" from inside an open group: the picker then
    // behaves as a source browser whose footer adds instead of creates.
    function beginAdd(themeName, toView) {
        addTheme = themeName
        view = toView
        filter = ""
        currentIndex = 0
        rebuildModel()
        Qt.callLater(extractTimer.restart)
    }

    function cancelAdd() {
        addTheme = ""
        view = "themes"
        rebuildModel()
    }

    // Esc / the breadcrumb: leave the deepest state you are in.
    function goBack() {
        if (addTheme !== "") { cancelAdd(); return }
        if (groupOpen) { closeGroup(); return }
        dismiss()
    }

    // ==================================================================
    // rename / delete the theme a card points at
    //
    // The picker never touches ~/.config/themes itself: theme-manage.py does
    // the path validation and the two regenerable derived files (shell
    // thumbnail, btop theme), and it refuses to delete the theme the desktop
    // is currently wearing — btop, hyprland and kitty still point at it.
    // ==================================================================
    property bool managing: false
    // `notice` deliberately outlives `statusMsg`: listProc wipes statusMsg the
    // moment the rescan lands, which would erase "renamed gruvbox" a frame
    // after it appeared.
    property string notice: ""
    Timer {
        id: noticeTimer
        interval: 3500
        repeat: false
        onTriggered: root.notice = ""
    }
    function say(msg) { root.notice = msg; noticeTimer.restart() }

    // The theme Rename / Delete act on: the group you are inside, or the group
    // card under the cursor. "" in Local, in wallhaven, and in add-mode.
    function targetGroup() {
        if (view !== "themes" || addTheme !== "") return ""
        if (groupOpen) return groupTheme
        const it = viewModel[currentIndex]
        if (it && it.kind === "group") return String(it.theme || "")
        return ""
    }

    // Directory names have to be slugs: theme-manage.py rejects anything else
    // before it is ever joined onto ~/.config/themes.
    function slugify(s) {
        return String(s).trim().toLowerCase()
            .replace(/\s+/g, "-")
            .replace(/[^a-z0-9._-]+/g, "-")
            .replace(/-+/g, "-")
            .replace(/^[-.]+/, "")
            .replace(/[-.]+$/, "")
            .slice(0, 64)
    }

    function renameTheme(from, to) {
        if (managing) return
        if (!from) { say("select a theme first"); return }
        const clean = slugify(to)
        if (!clean) { say("type a name first"); return }
        if (clean === from) return
        manageProc.op = "rename"
        manageProc.argA = from
        manageProc.argB = clean
        managing = true
        manageProc.running = true
    }

    function deleteTheme(name) {
        if (managing) return
        if (!name) { say("select a theme first"); return }
        manageProc.op = "delete"
        manageProc.argA = name
        manageProc.argB = ""
        managing = true
        manageProc.running = true
    }

    Process {
        id: manageProc
        property string op: "delete"
        property string argA: ""
        property string argB: ""
        property bool parsed: false
        running: false
        command: op === "rename"
            ? ["python3", root.manageScript, "rename", argA, argB]
            : ["python3", root.manageScript, "delete", argA]
        stdout: StdioCollector {
            onStreamFinished: {
                manageProc.parsed = true
                try {
                    const d = JSON.parse(text)
                    if (!d.ok) { root.say(String(d.error || "that did not work")); return }
                    if (manageProc.op === "delete") {
                        root.say("deleted " + manageProc.argA)
                        // Leaving a group you just deleted would keep drawing
                        // its cards until the rescan lands.
                        if (root.groupOpen && root.groupTheme === manageProc.argA)
                            root.closeGroup()
                    } else {
                        root.say("renamed " + manageProc.argA + " → " + d.name)
                        // Follow the rename instead of dropping back to the root.
                        if (root.groupOpen && root.groupTheme === manageProc.argA)
                            root.groupTheme = d.name
                    }
                    root.filter = ""
                    root.currentIndex = 0
                    root.rebuildModel()
                    root.refresh()
                    Qt.callLater(extractTimer.restart)
                } catch (e) {
                    root.say("theme operation failed")
                    console.warn("theme-manage parse:", e)
                }
            }
        }
        onExited: (code) => {
            if (code !== 0 && !manageProc.parsed)
                root.say("theme operation failed")
            manageProc.parsed = false
            root.managing = false
        }
    }

    // ==================================================================
    // the model the grid draws
    // ==================================================================
    function groupOf(name) {
        for (let i = 0; i < groups.length; ++i)
            if (groups[i].name === name) return groups[i]
        return null
    }

    function wallpaperCard(it, kind) {
        // `path` is the file that ends up as the theme background, and for
        // wallhaven it is a remote URL. `extract` is what the palette is read
        // from, so it must always be a local file — aether's cached 800 px
        // preview (or the wallhaven thumbnail), falling back to the original.
        const local = it.previewPath || it.thumbnailPath || it.path || ""
        return {
            kind: kind || "wallpaper",
            title: String(it.name || "").replace(/\.[^.]+$/, ""),
            sub: it.theme || "",
            preview: local,
            extract: local,
            path: it.path || "",
            theme: it.theme || "",
            id: it.id || "",
            remote: kind === "wallhaven"
        }
    }

    function matches(item, q) {
        if (!q) return true
        const s = q.toLowerCase()
        return item.title.toLowerCase().includes(s)
            || (item.sub && item.sub.toLowerCase().includes(s))
    }

    function rebuildModel() {
        let out = []
        if (view === "wallhaven") {
            out = whItems.map(it => wallpaperCard(it, "wallhaven"))
        } else if (view === "themes") {
            if (groupOpen) {
                const g = groupOf(groupTheme)
                if (g) out = g.wallpapers.map(it => wallpaperCard(it, "wallpaper"))
            } else {
                out = groups.map(g => ({
                    kind: "group",
                    title: g.name,
                    sub: g.count + (g.count === 1 ? " wallpaper" : " wallpapers"),
                    preview: g.cover,
                    path: "",
                    theme: g.name,
                    id: "",
                    remote: false
                }))
            }
        } else {
            out = localItems.map(it => wallpaperCard(it, "wallpaper"))
        }
        // The search box is sent to wallhaven as the query itself; re-filtering
        // the returned page by the same text client-side would delete every
        // result (wallhaven thumbnails carry no name to match against).
        const q = filter.trim()
        if (q && view !== "wallhaven") out = out.filter(it => matches(it, q))
        viewModel = out
        if (currentIndex >= out.length) currentIndex = Math.max(0, out.length - 1)
    }

    function selectedWallpaper() {
        const it = viewModel[currentIndex]
        if (!it || it.kind === "group" || !it.path) return null
        return it
    }

    function move(delta) {
        if (viewModel.length === 0) return
        currentIndex = (currentIndex + delta + viewModel.length) % viewModel.length
        Qt.callLater(extractTimer.restart)
    }

    function select(i) {
        if (i < 0 || i >= viewModel.length) return
        currentIndex = i
        Qt.callLater(extractTimer.restart)
    }

    // Enter / double-click on a card: groups open, wallpapers act.
    function activate() {
        const it = viewModel[currentIndex]
        if (!it) return
        if (it.kind === "group") { openGroup(it.theme); return }
        if (addTheme !== "") addToTheme()
        else create(true)              // Enter = create AND apply
    }

    function setFilter(f) {
        filter = f
        currentIndex = 0
        rebuildModel()
        if (view === "wallhaven") whSearchTimer.restart()
        else Qt.callLater(extractTimer.restart)
    }

    // ==================================================================
    // wallhaven
    // ==================================================================
    function setSorting(id) {
        if (whSorting === id) return
        whSorting = id
        whSearchTimer.restart()
    }
    function whSearchKey() { return whSorting + "|" + filter.trim() }

    function whSearch() {
        if (view !== "wallhaven") return
        if (whSearchProc.running) { whDirty = true; return }
        whAppending = false
        whSearching = true
        whSearchProc.q = filter.trim()
        whSearchProc.sorting = whSorting
        whSearchProc.pg = 1
        whSearchProc.running = true
    }

    // Infinite scroll (replaces the old ◀ ▶ pager): AetherGrid calls this
    // when the viewport reaches the end of the loaded results. One page at
    // a time; the next page is requested speculatively (whPage only advances
    // when the response echoes it back), so a failed fetch retries the same
    // page instead of skipping it. New searches/sortings reset to page 1 via
    // whSearch() and replace the list as before.
    //
    // A call that lands while a fetch is still exiting (stdout already
    // closed and parsed, QProcess not yet reaped — observed on slow
    // wallhaven responses) parks in whMorePending and replays at exit,
    // otherwise the grid's one-shot signal would be lost and the next page
    // would never load until the user scrolled again.
    property bool whMorePending: false
    function whMore() {
        if (view !== "wallhaven") return
        if (whSearchProc.running) { whMorePending = true; return }
        if (whPage >= whLastPage) { whMorePending = false; return }
        whMorePending = false
        whAppending = true
        whSearching = true
        whSearchProc.q = filter.trim()
        whSearchProc.sorting = whSorting
        whSearchProc.pg = whPage + 1
        whSearchProc.running = true
    }
    property bool whDirty: false

    // ==================================================================
    // palette: extract -> (preset overrides) -> adjust
    // ==================================================================
    function paletteCacheKey(path, mode, light) {
        return mode + "|" + (light ? "light" : "dark") + "|" + path
    }

    function requestPalette() {
        const item = selectedWallpaper()
        if (!item) {
            basePalette = []; palette = []; paletteSource = ""; extracting = false
            return
        }
        if (presetActive && presets[presetName]) {
            basePalette = presets[presetName].slice(0, 16)
            paletteSource = item.extract
            extracting = false
            runAdjust()
            return
        }
        startExtractNow(item.extract)
    }

    // Called by the debounced timer: start unless one is already in flight,
    // in which case _drainPending picks the last request up.
    function startExtractNow(src) {
        if (!src) return
        if (extractProc.running) {
            pendingExtractPath = src
            pendingExtractLightMode = lightMode
            pendingExtractSession = sessionId
            return
        }
        _startExtract(src)
    }

    function _startExtract(src) {
        const key = paletteCacheKey(src, extractMode, lightMode)
        const cached = paletteCache[key]
        if (cached) {
            basePalette = cached.slice(0, 16)
            paletteSource = src
            extracting = false
            statusMsg = ""
            runAdjust()
            _drainPending(src)
            return
        }
        extracting = true
        statusMsg = ""
        extractProc.forPath = src
        extractProc.forKey = key
        extractProc.forSession = sessionId
        extractProc.outputFinished = false
        extractProc.processExited = false
        extractProc.running = true
    }

    function _drainPending(justFinished) {
        if (pendingExtractPath && pendingExtractSession === sessionId
                && pendingExtractPath !== justFinished) {
            const next = pendingExtractPath
            pendingExtractPath = ""
            Qt.callLater(() => root._startExtract(next))
        } else {
            pendingExtractPath = ""
        }
    }

    function runAdjust() {
        if (basePalette.length < 16) { palette = []; return }
        const args = adjustArgs()
        if (args.length === 0) {
            palette = basePalette.slice(0, 16)
            adjusting = false
            return
        }
        const key = basePalette.join(",") + "|" + args.join(" ")
        if (adjustCache[key]) {
            palette = adjustCache[key].slice(0, 16)
            adjusting = false
            return
        }
        adjusting = true
        adjustProc.forArgs = args
        adjustProc.forKey = key
        adjustProc.forSession = sessionId
        adjustProc.outputFinished = false
        adjustProc.processExited = false
        adjustProc.running = true
    }

    // Only send what differs from aether's defaults — fewer argv, and the
    // command line doubles as a readable record of the edit.
    function adjustArgs() {
        if (!dataLoaded) return []
        const flag = {
            vibrance: "--vibrance", saturation: "--saturation",
            contrast: "--contrast", brightness: "--brightness",
            shadows: "--shadows", highlights: "--highlights",
            hueShift: "--hue-shift", temperature: "--temperature",
            tint: "--tint", gamma: "--gamma",
            blackPoint: "--black-point", whitePoint: "--white-point"
        }
        const out = []
        for (const k in flag) {
            if (!(k in limits)) continue
            const v = Number(adjustments[k])
            if (v !== limits[k].default) out.push(flag[k], String(v))
        }
        return out
    }

    function setAdjust(key, value) {
        if (!(key in limits)) return
        const lo = limits[key].min, hi = limits[key].max
        const next = Math.max(lo, Math.min(hi, Number(value)))
        const merged = Object.assign({}, adjustments)
        merged[key] = next
        adjustments = merged
        adjustTimer.restart()
    }

    function resetAdjustments() {
        adjustments = defaultAdjustments()
        adjustTimer.restart()
    }

    // aether's own nudge row: ±15° hue, ±15% saturation, cooler/warmer.
    function nudge(kind) {
        const at = k => Number(adjustments[k] || 0)
        const set = (k, v) => setAdjust(k, v)
        if (kind === "hueDown") set("hueShift", at("hueShift") - 15)
        else if (kind === "hueUp") set("hueShift", at("hueShift") + 15)
        else if (kind === "desat") set("saturation", at("saturation") - 15)
        else if (kind === "sat") set("saturation", at("saturation") + 15)
        else if (kind === "cool") set("temperature", at("temperature") - 15)
        else if (kind === "warm") set("temperature", at("temperature") + 15)
    }

    function setExtractMode(m) {
        if (extractMode === m) return
        extractMode = m
        paletteCache = ({})          // a different mode invalidates every preview
        // An active preset pins the palette (requestPalette short-circuits to
        // it), so a mode change would silently do nothing and the dropdown
        // would look broken. Drop the preset and re-extract from the wallpaper.
        if (presetActive) { presetActive = false; presetName = ""; statusMsg = "preset cleared" }
        extractTimer.restart()
    }

    function setLightMode(on) {
        if (lightMode === on) return
        lightMode = on
        paletteCache = ({})
        if (presetActive) { presetActive = false; presetName = ""; statusMsg = "preset cleared" }
        else statusMsg = on ? "light mode" : "dark mode"
        extractTimer.restart()
    }
    function toggleLight() { setLightMode(!lightMode) }

    function applyPreset(name) {
        if (!presets[name]) return
        presetActive = true
        presetName = name
        requestPalette()
    }
    function clearPreset() {
        if (!presetActive) return
        presetActive = false
        presetName = ""
        paletteCache = ({})
        extractTimer.restart()
    }

    // ==================================================================
    // create / add
    // ==================================================================
    // Create builds a brand new theme; addToTheme only ever drops a file into
    // an existing theme's backgrounds/. Neither path rewrites a colour of a
    // theme it did not make — that guarantee lives in aether-apply.sh.
    function create(withApply) {
        if (applying) return
        const item = selectedWallpaper()
        if (!item) { statusMsg = "select a wallpaper first"; return }
        if (palette.length !== 16) { statusMsg = "palette is not ready yet"; return }
        createWithApply = withApply
        if (item.remote) { startDownload(item); return }
        runApply(item.path, palette)
    }

    function addToTheme() {
        if (applying) return
        const item = selectedWallpaper()
        if (!item) { statusMsg = "select a wallpaper first"; return }
        if (item.remote) { startDownload(item); return }   // adds on completion
        runAdd(item.path)
    }

    function runApply(path, colors) {
        applying = true
        statusMsg = (createWithApply ? "Creating theme ..." : "Saving theme ...")
        applyProc.forPath = path
        applyProc.forPalette = JSON.stringify(colors.slice(0, 16))
        applyProc.forLightMode = lightMode
        applyProc.forApply = createWithApply
        applyProc.forAddTo = ""
        applyProc.forSession = sessionId
        applyProc.running = true
    }

    function runAdd(path) {
        applying = true
        statusMsg = "Adding to " + addTheme + " ..."
        applyProc.forPath = path
        applyProc.forPalette = ""
        applyProc.forApply = false
        applyProc.forAddTo = addTheme
        applyProc.forSession = sessionId
        applyProc.running = true
    }

    // ==================================================================
    // Subprocesses
    // ==================================================================

    // Local + grouped listing. scripts/aether-list.py merges aether's own
    // recursive scan (which supplies cached 800 px previews) with a direct
    // scan of ~/.config/themes/*/backgrounds — one theme file exists only in
    // the theme dir, so neither source alone is complete.
    Process {
        id: listProc
        running: false
        command: ["python3", root.listScript]
        stdout: StdioCollector {
            onStreamFinished: {
                root.listLoaded = true
                try {
                    const d = JSON.parse(text)
                    if (d.error) { root.listError = String(d.error); return }
                    root.groups = d.themes || []
                    root.localItems = d.local || []
                    root.listError = ""
                    // The group you were looking at may have vanished.
                    if (root.groupOpen && !root.groupOf(root.groupTheme))
                        root.groupOpen = false
                    root.rebuildModel()
                    if (!root.busy) root.statusMsg = ""
                    Qt.callLater(extractTimer.restart)
                } catch (e) {
                    root.listError = "listing failed"
                    console.warn("aether list parse:", e)
                }
            }
        }
    }

    Process {
        id: extractProc
        property string forPath: ""
        property string forKey: ""
        property int forSession: 0
        property bool outputFinished: false
        property bool processExited: false
        running: false

        function finishRequest() {
            if (!outputFinished || !processExited) return
            root.extracting = false
            root._drainPending(forPath)
        }

        command: {
            const cmd = ["aether", "--extract-palette", forPath,
                         "--extract-mode", root.extractMode]
            if (root.lightMode) cmd.push("--light-mode")
            cmd.push("--json")
            return cmd
        }
        stdout: StdioCollector {
            onStreamFinished: {
                if (extractProc.forSession === root.sessionId && text) {
                    try {
                        const d = JSON.parse(text)
                        if (Array.isArray(d.colors) && d.colors.length >= 16) {
                            const c = d.colors.slice(0, 16)
                            root.paletteCache[extractProc.forKey] = c
                            const item = root.selectedWallpaper()
                            // Match on the source we actually requested
                            // (item.extract), not item.path: for wallhaven the
                            // path is a remote URL and for local wallpapers it
                            // is the full-size original, neither of which is
                            // what the extraction read.
                            if (item && item.extract === extractProc.forPath
                                    && extractProc.forSession === root.sessionId) {
                                root.basePalette = c
                                root.paletteSource = extractProc.forPath
                                root.statusMsg = ""
                                root.runAdjust()
                            }
                        } else if (d.error) {
                            root.statusMsg = String(d.error)
                        }
                    } catch (e) { console.warn("aether extract parse:", e) }
                }
                extractProc.outputFinished = true
                extractProc.finishRequest()
            }
        }
        onExited: (code) => {
            extractProc.processExited = true
            extractProc.finishRequest()
        }
    }

    Process {
        id: adjustProc
        property var forArgs: []
        property string forKey: ""
        property int forSession: 0
        property bool outputFinished: false
        property bool processExited: false
        running: false

        function finishRequest() {
            if (!outputFinished || !processExited) return
            root.adjusting = false
        }

        command: ["aether", "--adjust-palette", JSON.stringify(root.basePalette)]
                 .concat(forArgs).concat(["--json"])
        stdout: StdioCollector {
            onStreamFinished: {
                if (adjustProc.forSession === root.sessionId && text) {
                    try {
                        const d = JSON.parse(text)
                        if (Array.isArray(d.output) && d.output.length >= 16) {
                            const c = d.output.slice(0, 16)
                            root.adjustCache[adjustProc.forKey] = c
                            root.palette = c
                        } else if (d.error) {
                            root.statusMsg = String(d.error)
                        }
                    } catch (e) { console.warn("aether adjust parse:", e) }
                }
                adjustProc.outputFinished = true
                adjustProc.finishRequest()
            }
        }
        onExited: () => {
            adjustProc.processExited = true
            adjustProc.finishRequest()
        }
    }

    // wallhaven: 1 page = 24 results. `--sorting` is aether's own filter set
    // (toplist / date_added / random / relevance / views / favorites).
    Process {
        id: whSearchProc
        property string q: ""
        property string sorting: "toplist"
        property int pg: 1
        running: false
        command: ["aether", "--wallhaven-thumbs", q,
                  "--sorting", sorting, "--page", String(pg),
                  "--json", "--pages", "1"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (Array.isArray(d.wallpapers)) {
                        const items = d.wallpapers.map(w => ({
                            name: (w.resolution ? w.resolution + "  " : "") + (w.id || ""),
                            path: w.path || "",
                            previewPath: w.thumbnailPath || w.thumbURL || "",
                            id: w.id || "",
                            theme: "",
                            size: 1
                        }))
                        if (d.meta) {
                            // append runs speculatively (whPage is not
                            // advanced before the request), so fall back to
                            // the page actually requested if the echo is
                            // missing — otherwise page 2 would re-request
                            root.whPage = d.meta.current_page || whSearchProc.pg
                            root.whLastPage = d.meta.last_page || 1
                            root.whTotal = d.meta.total || 0
                        }
                        root.whLoadedFor = whSearchProc.sorting + "|" + whSearchProc.q
                        root.whSearching = false
                        if (root.whAppending) {
                            // infinite scroll: grow the list in place — the
                            // selection and the grid's scroll position must
                            // not jump when the new page lands under it
                            root.whAppending = false
                            root.whItems = root.whItems.concat(items)
                        } else {
                            root.whItems = items
                            root.currentIndex = 0
                            if (root.whItems.length) Qt.callLater(extractTimer.restart)
                        }
                        root.rebuildModel()
                        root.statusMsg = root.whItems.length === 0 ? "no wallhaven results" : ""
                    } else if (d.error) {
                        root.statusMsg = String(d.error)
                    }
                } catch (e) {
                    root.statusMsg = "wallhaven search failed"
                    console.warn("wallhaven parse:", e)
                }
            }
        }
        onExited: () => {
            root.whSearching = false
            if (root.whDirty) {
                root.whDirty = false
                Qt.callLater(() => root.whSearch())
            }
            // a whMore() that arrived during this run's exit window replays
            // now that the proc is genuinely free (see whMorePending)
            if (root.whMorePending) {
                root.whMorePending = false
                Qt.callLater(() => root.whMore())
            }
        }
    }

    Timer {
        id: whSearchTimer
        interval: 450
        repeat: false
        onTriggered: root.whSearch()
    }

    // wallhaven cards act on the CDN URL, so the full image has to land on
    // disk before it can become a theme (or a theme's extra background).
    Process {
        id: whDownloadProc
        property string forId: ""
        property int forSession: 0
        property string downloadedPath: ""
        // StdioCollector can finish AFTER the process exits, so a plain
        // onExited would sometimes read an empty path and report failure for
        // a download that actually succeeded. Same two-flag handshake the
        // palette extractor uses.
        property bool outputFinished: false
        property bool processExited: false
        property string thenRun: ""    // "apply" | "add"
        running: false

        function finishRequest() {
            if (!outputFinished || !processExited) return
            if (forSession !== root.sessionId) { root.applying = false; return }
            if (!downloadedPath) {
                root.applying = false
                root.statusMsg = "download failed"
                return
            }
            if (thenRun === "add") root.runAdd(downloadedPath)
            else root.runApply(downloadedPath, root.palette)
        }

        command: ["aether", "--wallhaven-download", forId, "--json"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const d = JSON.parse(text)
                    if (d && d.path) whDownloadProc.downloadedPath = d.path
                } catch (e) { console.warn("wallhaven download parse:", e) }
                whDownloadProc.outputFinished = true
                whDownloadProc.finishRequest()
            }
        }
        onExited: () => {
            whDownloadProc.processExited = true
            whDownloadProc.finishRequest()
        }
    }

    function startDownload(item) {
        if (!item || !item.id || applying) return
        applying = true
        statusMsg = "downloading " + item.id + " ..."
        whDownloadProc.forId = item.id
        whDownloadProc.forSession = sessionId
        whDownloadProc.downloadedPath = ""
        whDownloadProc.thenRun = addTheme !== "" ? "add" : "apply"
        whDownloadProc.outputFinished = false
        whDownloadProc.processExited = false
        whDownloadProc.running = true
    }

    Process {
        id: applyProc
        property string forPath: ""
        property string forPalette: ""
        property bool forLightMode: false
        property bool forApply: true
        property string forAddTo: ""
        property int forSession: 0
        running: false
        command: {
            const cmd = ["bash", root.applyScript, forPath]
            if (forAddTo !== "") cmd.push("--add-to", forAddTo)
            else {
                if (forPalette !== "") cmd.push("--palette", forPalette)
                else cmd.push("--mode", root.extractMode)
                if (forLightMode) cmd.push("--light")
                if (!forApply) cmd.push("--no-apply")
            }
            return cmd
        }
        onExited: (code) => {
            root.applying = false
            if (applyProc.forSession !== root.sessionId) return
            if (code === 0) {
                const added = applyProc.forAddTo !== ""
                root.statusMsg = added
                    ? "wallpaper added to " + applyProc.forAddTo
                    : "theme created"
                if (added) {
                    root.addTheme = ""
                    root.view = "themes"
                    // Land inside the theme you just added to. groupTheme must
                    // be set here: beginAdd() only sets addTheme, and the list
                    // rescan below clears groupOpen when it cannot resolve an
                    // empty groupTheme — which would dump you at the root
                    // instead of showing the wallpaper you just added.
                    root.groupTheme = applyProc.forAddTo
                    root.groupOpen = true
                    root.currentIndex = 0
                    root.rebuildModel()
                }
                // Stay open so you can keep trying wallpapers; Esc closes.
                // The rescan also picks the wallpaper that was just added.
                root.refresh()
            } else {
                root.statusMsg = added ? "add failed" : "create failed"
            }
        }
    }

    Timer {
        id: extractTimer
        interval: 200
        repeat: false
        onTriggered: root.requestPalette()
    }

    Timer {
        id: adjustTimer
        interval: 150
        repeat: false
        onTriggered: root.runAdjust()
    }

    IpcHandler {
        target: "aether"
        function toggle(): void { root.toggle() }
        function open(): void { root.openPicker() }
        function close(): void { root.closePicker() }
        function toggleLight(): void { root.toggleLight() }
        function wallhaven(): void { root.setView("wallhaven") }
        // testing / scripting hooks
        function view(name: string): void { root.setView(name) }
        function openGroup(name: string): void { root.openGroup(name) }
        function setFilter(q: string): void { root.setFilter(q) }
        function setSorting(s: string): void { root.setSorting(s) }
        // testing hook: what the grid's scroll trigger calls
        function whNext(): void { root.whMore() }
        function setMode(m: string): void { root.setExtractMode(m) }
        function preset(name: string): void { root.applyPreset(name) }
        function clearPreset(): void { root.clearPreset() }
        function setAdjust(key: string, value: string): void {
            root.setAdjust(key, Number(value))
        }
        function resetAdjusts(): void { root.resetAdjustments() }
        function select(i: string): void { root.select(Number(i)) }
        function move(d: string): void { root.move(Number(d)) }
        function create(apply: string): void { root.create(apply !== "0") }
        function add(): void { root.addToTheme() }
        function beginAdd(theme: string, viewName: string): void {
            root.beginAdd(theme, viewName)
        }
        function goBack(): void { root.goBack() }
        function rename(from: string, to: string): void { root.renameTheme(from, to) }
        function remove(name: string): void { root.deleteTheme(name) }
        function status(): string {
            const it = root.viewModel[root.currentIndex]
            return JSON.stringify({
                open: root.open,
                view: root.view,
                groupOpen: root.groupOpen,
                group: root.groupTheme,
                addTheme: root.addTheme,
                groups: root.groups.length,
                local: root.localItems.length,
                count: root.viewModel.length,
                index: root.currentIndex,
                kind: it ? it.kind : "",
                path: it ? it.path : "",
                mode: root.extractMode,
                lightMode: root.lightMode,
                preset: root.presetActive ? root.presetName : "",
                palette: root.palette,
                extracting: root.extracting,
                adjusting: root.adjusting,
                applying: root.applying,
                whSearching: root.whSearching,
                whTotal: root.whTotal,
                whPage: root.whPage,
                whLastPage: root.whLastPage,
                target: root.targetGroup(),
                managing: root.managing,
                notice: root.notice,
                status: root.statusMsg
            })
        }
    }
}
