pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Waybar analogy: nothing quite like this in Waybar since it's not a bar
// module at all — closest is a rofi/wofi script, except state persists here
// so the grid doesn't need to re-scan from scratch every keypress.
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

    property var wallpapers: []   // absolute file paths for the active theme
    property int selectedIndex: 0

    // the wallpaper actually on screen (rendered by Background.qml) —
    // plain-path state file, same idea as Colors.qml's colors.json.
    // previous/previousOpacity drive the crossfade between the two.
    property string current: ""
    property string previous: ""
    property real previousOpacity: 0
    property bool stateLoaded: false   // first FileView load settled?

    readonly property string statePath:
        Quickshell.env("HOME") + "/.local/state/quickshell/current-wallpaper"

    readonly property string themeDir: Themes.currentTheme !== ""
        ? Quickshell.env("HOME") + "/.config/themes/" + Themes.currentTheme + "/backgrounds"
        : ""

    function scan() {
        if (root.themeDir === "") { root.wallpapers = []; return }
        scanProc.command = ["bash", "-c",
            "find '" + root.themeDir + "' -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort"]
        scanProc.running = true
    }

    function openPicker() {
        root.scan()
        // land the selection on the wallpaper that's actually set, so the
        // strip opens with the active one highlighted
        root.selectedIndex = Math.max(0, root.wallpapers.indexOf(root.current))
        root.open = true
    }

    function closePicker() { root.open = false }
    function toggle() { root.open ? root.closePicker() : root.openPicker() }

    function setCurrent(path, instant) {
        path = String(path || "").trim()
        if (path === root.current) return
        root.previous = instant ? "" : root.current
        root.current = path
        fadeOut.restart()
    }

    // no daemon to talk to — quickshell draws the wallpaper itself in
    // Background.qml, so "applying" is just swapping service state and
    // persisting the path. Written in place (printf >, never mv) so the
    // FileView's inotify watch survives — same lesson as colors.json.
    function apply(path) {
        path = String(path || "").trim()
        if (path === "" || path === root.current) return
        root.setCurrent(path, false)
        stateWriteProc.command = ["bash", "-c", 'printf %s "$1" > "$2"', "qs", path, root.statePath]
        stateWriteProc.running = true
    }

    function applySelected() {
        if (root.wallpapers.length === 0) return
        root.apply(root.wallpapers[root.selectedIndex])
    }

    // switch-theme.sh's default rule, mirrored: default.* if the theme has
    // one, else first of the sorted scan (omarchy: sort | head -1).
    function pickDefault() {
        for (let i = 0; i < root.wallpapers.length; i++) {
            const base = root.wallpapers[i].split("/").pop().toLowerCase()
            if (base.startsWith("default.")) return root.wallpapers[i]
        }
        return root.wallpapers.length > 0 ? root.wallpapers[0] : ""
    }

    // first run: no state file yet — adopt the active theme's default,
    // same spirit as omarchy's upgrade script bootstrapping its
    // background symlink from the theme's backgrounds folder.
    function maybeBootstrap() {
        if (!root.stateLoaded || root.current !== "") return
        const def = root.pickDefault()
        if (def !== "") root.apply(def)
    }

    // delta 1/-1 = left/right, 3/-3 = down/up (3 = grid column count)
    function moveSelection(delta) {
        if (root.wallpapers.length === 0) return
        root.selectedIndex = (root.selectedIndex + delta + root.wallpapers.length) % root.wallpapers.length
    }

    Process {
        id: scanProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.wallpapers = text.split("\n").filter(t => t.length > 0)
                // picker open while the list swapped under it (switched
                // theme, then reopened fast): re-land the hero on the
                // active wallpaper — an index into the OLD theme's list
                // means nothing here (this used to open on a random file)
                if (root.open)
                    root.selectedIndex = Math.max(0, root.wallpapers.indexOf(root.current))
                root.maybeBootstrap()
            }
        }
    }

    Process { id: stateWriteProc }

    // crossfade: Background.qml keeps `previous` layered over `current`
    // and pulls it away with this.
    NumberAnimation {
        id: fadeOut
        target: root
        property: "previousOpacity"
        from: 1
        to: 0
        duration: Motion.medium3
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.standardCurve
    }

    FileView {
        path: root.statePath
        watchChanges: true
        printErrors: false
        onLoaded: {
            root.stateLoaded = true
            root.setCurrent(String(text()).trim(), false)
            root.maybeBootstrap()
        }
        onFileChanged: reload()
    }

    // if the state file doesn't exist, loaded() never fires — don't let
    // the first-run bootstrap wait on it forever.
    Timer {
        interval: 400
        running: true
        onTriggered: {
            if (!root.stateLoaded) {
                root.stateLoaded = true
                root.maybeBootstrap()
            }
        }
    }

    // "every time i switch a theme, wallpaper selector shows images of
    // that theme" — re-scan the instant currentTheme changes, not just
    // lazily whenever the picker next opens.
    Connections {
        target: Themes
        function onCurrentThemeChanged() { root.scan() }
    }

    IpcHandler {
        target: "wallpaper"
        function toggle(): void { root.toggle() }
        // for scripts / hypr binds: qs ipc call wallpaper set /path/to.jpg
        function set(path: string): void { root.apply(path) }
    }

    Component.onCompleted: scan()
}
