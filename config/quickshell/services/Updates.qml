pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Waybar analogy: same idea as a "custom/updates" module running a script
// on a long interval (updates don't need second-by-second polling), except
// state lives here so the bar icon and the popup both read the same list.
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

    property var packages: []   // [{ name, oldVersion, newVersion, aur }]
    readonly property int count: packages.length

    function toggle() { open = !open }
    function close() { open = false }

    // ---- monthly nudge gate for the bar's activity chip ----
    // The check itself can keep running every 30 min (read-only, no
    // download risk) — but the CHIP only re-appears once a month. That's
    // the anti-instability rule: you get one reminder per cycle to batch
    // updates, instead of a standing invitation to chase brand-new
    // (potentially unstable) packages. Once shown, it stays shown until
    // the count clears (updates installed), then the next nudge arms
    // 30 days out.
    readonly property bool nudgePending:
        count > 0 && Date.now() >= Number(Settings.get("updates.nextNudge", 0))
    readonly property bool showNudge:
        count > 0 && (nudgePending || Settings.get("updates.nudgeShown", false) === true)

    onShowNudgeChanged: {
        if (showNudge) {
            if (Settings.get("updates.nudgeShown", false) !== true)
                Settings.set("updates.nudgeShown", true)
            if (nudgePending)
                Settings.set("updates.nextNudge", Date.now() + 30 * 24 * 3600 * 1000)
        } else if (count === 0) {
            // cycle over — disarm so the next batch of updates nudges again
            if (Settings.get("updates.nudgeShown", false) === true)
                Settings.set("updates.nudgeShown", false)
        }
    }

    function refresh() {
        pacmanCheck.running = true
        aurCheck.running = true
    }

    property var _pacmanResults: []
    property var _aurResults: []

    function _parseLine(line, aur) {
        // format from both checkupdates and `yay -Qua`: "name oldver -> newver"
        const m = line.match(/^(\S+)\s+(\S+)\s+->\s+(\S+)/)
        if (!m) return null
        return { name: m[1], oldVersion: m[2], newVersion: m[3], aur: aur }
    }

    // checkupdates exits with code 2 and no output when there's nothing
    // pending — that's a normal "up to date" result, not an error.
    Process {
        id: pacmanCheck
        command: ["checkupdates"]
        property var _lines: []
        onRunningChanged: {
            if (running) {
                _lines = []
            } else {
                root._pacmanResults = _lines.map(l => root._parseLine(l, false)).filter(p => p !== null)
                root.packages = root._pacmanResults.concat(root._aurResults)
            }
        }
        stdout: SplitParser {
            onRead: line => pacmanCheck._lines.push(line)
        }
    }

    // ASSUMPTION: yay is your AUR helper. Swap the command to `paru -Qua`
    // if that's what you actually use — output format is the same
    // convention either way, so the parser doesn't need to change.
    Process {
        id: aurCheck
        command: ["yay", "-Qua"]
        property var _lines: []
        onRunningChanged: {
            if (running) {
                _lines = []
            } else {
                root._aurResults = _lines.map(l => root._parseLine(l, true)).filter(p => p !== null)
                root.packages = root._pacmanResults.concat(root._aurResults)
            }
        }
        stdout: SplitParser {
            onRead: line => aurCheck._lines.push(line)
        }
    }

    Timer {
        interval: 1800000   // 30 min
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    function upgradeAll() {
        upgradeProc.running = true
    }

    // Runs interactively in a real terminal — sudo needs an actual TTY for
    // the password prompt, so this can't be a silent background Process.
    // ASSUMPTION: kitty is your terminal, per your theme setup notes.
    Process {
        id: upgradeProc
        command: ["kitty", "-e", "sh", "-c", "yay -Syu; echo; echo Done — press Enter to close; read _"]
    }

    // same IPC pattern as ControlCenter/PowerMenu — Hyprland keybind entry point
    IpcHandler {
        target: "updates"
        function toggle(): void { root.toggle() }
    }
}
