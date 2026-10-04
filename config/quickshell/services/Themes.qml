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

    property string currentTheme: ""
    property var themes: []
    // theme name -> its screenshot thumbnail, and -> its wallpaper. Both are
    // resolved by the scan below rather than guessed in QML:
    //   · the screenshot only exists for themes that have been through
    //     scripts/generate-previews.sh (the omarchy ones) — everything
    //     aether creates has none, which is why those cards used to fall
    //     straight to the palette stripes;
    //   · the wallpaper's extension follows whatever the source file was
    //     (default.jpg, or default.png for a PNG source), and probing for it
    //     here means a path that does not exist never reaches an Image.
    property var previewOf: ({})
    property var wallpaperOf: ({})
    property int selectedIndex: 0
    property string query: ""

    // picker size (1/2/3) — persisted in ~/.local/state/quickshell/picker-size
    // so the choice survives quickshell restarts: setSize writes the file,
    // the FileView below loads it on startup.
    property int size: 2

    // per-size geometry in ONE table — M3 CENTER-ALIGNED HERO carousel
    // (https://m3.material.io/components/carousel/guidelines): one large
    //16:9 hero card (selected theme, uncropped) + every other theme as a
    // small vertical rectangle; only hero + two smalls fit the container.
    // pillW = pads + small + gap + hero + gap + small +24 pill margins;
    // listH =8 + heroH +4 +16 label +8. Spacing/pads/radius per spec.
    // Read by Bar.qml (pill target size) and PillThemeContent.qml (cards).
    readonly property var geom: ({
        1: { pillW: 424, listH: 162, hw: 224, hh: 126, sw: 64, sh: 90,  spacing: 8, padX: 16, padY: 8, radius: 28, font: 11 },
        2: { pillW: 472, listH: 180, hw: 256, hh: 144, sw: 72, sh: 100, spacing: 8, padX: 16, padY: 8, radius: 28, font: 12 },
        3: { pillW: 520, listH: 198, hw: 288, hh: 162, sw: 80, sh: 112, spacing: 8, padX: 16, padY: 8, radius: 28, font: 13 }
    })[Math.min(3, Math.max(1, size))]

    function setSize(s) {
        const n = Math.min(3, Math.max(1, parseInt(s) || 1))
        size = n
        sizeWriteProc.command = ["bash", "-c", 'printf %s "$1" > "$2"', "qs",
            String(n), Quickshell.env("HOME") + "/.local/state/quickshell/picker-size"]
        sizeWriteProc.running = true
    }

    // the picker's filtered view — launcher-style: prefix matches first,
    // then substring, both alphabetical (scan already yields sorted names)
    readonly property var visibleThemes: {
        const q = query.trim().toLowerCase()
        if (q === "") return themes
        const prefix = [], inside = []
        themes.forEach(t => {
            const lt = t.toLowerCase()
            if (lt.startsWith(q)) prefix.push(t)
            else if (lt.includes(q)) inside.push(t)
        })
        return prefix.concat(inside)
    }

    // typing re-scopes the list — land the highlight on the first match
    onQueryChanged: selectedIndex = 0

    function scan() {
        scanProc.running = true
    }

    function openPicker() {
        scan()
        // fresh search state every open (clear before picking the index so
        // onQueryChanged can't stomp the current-theme landing spot)
        query = ""
        // land the highlight (the enlarged card) on the theme you're already
        // using instead of always the first one in the list
        const i = themes.indexOf(currentTheme)
        selectedIndex = i >= 0 ? i : 0
        open = true
    }

    function closePicker() {
        open = false
        query = ""
    }

    // Applies are expensive (python + hyprctl reload) and rapid carousel
    // steps would race: while a switch runs, remember only the LAST
    // requested name and run it when the current one exits — every step
    // still lands, the system theme always settles on what's selected.
    property string pendingApply: ""

    // ThemeFlip.qml hangs the frozen-frame reveal off these: started
    // fires once per switch, before the script starts and before anything
    // on screen changes; finished fires only when nothing else is queued
    // — pending applies re-enter apply() first and fire started again.
    signal applyStarted()
    signal applyFinished()

    function apply(name) {
        if (!name) return
        currentTheme = name
        closePicker()
        if (applyProc.running) {
            pendingApply = name
            return
        }
        pendingApply = ""
        applyStarted()
        applyProc.command = ["bash", Quickshell.shellDir + "/scripts/switch-theme.sh", name]
        applyProc.running = true
    }

    // called by Enter — applies whichever VISIBLE swatch is highlighted
    function applySelected() {
        const list = visibleThemes
        if (list.length === 0) return
        apply(list[Math.min(selectedIndex, list.length - 1)])
    }

    // delta of 1/-1 = left/right over the FILTERED list
    function moveSelection(delta) {
        const list = visibleThemes
        if (list.length === 0) return
        selectedIndex = (selectedIndex + delta + list.length) % list.length
    }

    Process {
        id: scanProc
        // name TAB screenshot TAB wallpaper, one line per theme. The scan
        // stat()s both images so the pickers get a concrete path (or "")
        // instead of assembling a URL for a file that may not be there —
        // a misspelled extension used to surface as "Cannot open" in the log
        // and a silent drop back to the stripes.
        command: ["bash", "-c", [
            'shopt -s nullglob',
            'shot="$HOME/.local/state/quickshell/generated/thumbnails"',
            'for t in "$HOME"/.config/themes/*/; do',
            '    n=$(basename "$t")',
            '    s=""; [ -f "$shot/$n.png" ] && s="$shot/$n.png"',
            '    w=""',
            '    if [ -d "$t"backgrounds ]; then',
            '        for f in "$t"backgrounds/default.jpg "$t"backgrounds/default.jpeg \\',
            '                 "$t"backgrounds/default.png "$t"backgrounds/default.webp; do',
            '            [ -f "$f" ] && { w="$f"; break; }',
            '        done',
            '        if [ -z "$w" ]; then',
            '            first=$(ls -1 "$t"backgrounds | head -1)',
            '            [ -n "$first" ] && w="$t"backgrounds/"$first"',
            '        fi',
            '    fi',
            '    printf \'%s\\t%s\\t%s\\n\' "$n" "$s" "$w"',
            'done'
        ].join("\n")]
        stdout: StdioCollector {
            onStreamFinished: {
                const names = [], shot = {}, wall = {}
                text.split("\n").forEach(line => {
                    if (!line) return
                    const c = line.split("\t")
                    names.push(c[0])
                    shot[c[0]] = c[1] || ""
                    wall[c[0]] = c[2] || ""
                })
                // maps first, names last: a delegate only ever appears once
                // the paths it binds to are already in place
                root.previewOf = shot
                root.wallpaperOf = wall
                root.themes = names
            }
        }
    }

    // restore the last applied theme (written by switch-theme.sh) so the
    // wallpaper picker / anything reading currentTheme survives restarts
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/current-theme"
        watchChanges: true
        printErrors: false
        onLoaded: {
            const t = text().trim()
            if (t.length > 0) root.currentTheme = t
        }
        onFileChanged: reload()
    }

    // restore the chosen picker size (written by setSize above); missing
    // file just means the default (2) until the user picks one
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/picker-size"
        printErrors: false
        onLoaded: {
            const v = parseInt(text().trim())
            if (v >= 1 && v <= 3) root.size = v
        }
    }

    Process {
        id: applyProc
        onExited: {
            if (root.pendingApply !== "") {
                const n = root.pendingApply
                root.pendingApply = ""
                root.apply(n)
            } else {
                root.applyFinished()
            }
        }
    }
    Process { id: sizeWriteProc }

    IpcHandler {
        target: "theme"
        function toggle(): void {
            if (root.open) root.closePicker()
            else root.openPicker()
        }
        function apply(name: string): void {
            root.apply(name)
        }
        // also handy from scripts: qs ipc call theme setQuery "nord"
        function setQuery(q: string): void {
            root.query = q
        }
        // qs ipc call theme setSize 2   —1/2/3 comparison hook
        function setSize(s: string): void {
            root.setSize(s)
        }
    }

    Component.onCompleted: scan()
}






// pragma Singleton
// import Quickshell
// import Quickshell.Io
// import QtQuick
//
// Singleton {
//     id: root
//
//     property bool open: false
//     property string currentTheme: ""
//     property var themes: []
//
//     function scan() {
//         scanProc.running = true
//     }
//
//     function openPicker() {
//         scan()
//         open = true
//     }
//
//     function closePicker() {
//         open = false
//     }
//
//     function apply(name) {
//         applyProc.command = ["bash", Quickshell.shellDir + "/scripts/switch-theme.sh", name]
//         applyProc.running = true
//         currentTheme = name
//         closePicker()
//     }
//
//     Process {
//         id: scanProc
//         command: ["bash", "-c", "ls -1 " + Quickshell.env("HOME") + "/.config/theme"]
//         stdout: StdioCollector {
//             onStreamFinished: root.themes = text.split("\n").filter(t => t.length > 0)
//         }
//     }
//
//     Process { id: applyProc }
//
//     IpcHandler {
//         target: "theme"
//         function toggle(): void {
//             if (root.open) root.closePicker()
//             else root.openPicker()
//         }
//         function apply(name: string): void {
//             root.apply(name)
//         }
//     }
//
//     Component.onCompleted: scan()
// }
