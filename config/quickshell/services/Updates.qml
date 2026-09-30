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

    // ---- desktop (repo) updates: a deploy pushed to GitHub -------------
    // Distinct from the package list above: this tracks the git remote
    // the clone came from, so a pushed selah commit surfaces as a popup
    // with Update / Later instead of relying on the user to know to
    // `git pull`. Dismissal is per-sha (dismissedSha): "Later" silences
    // THIS version for good, the next deploy pops again.
    property string repoState: "unknown"     // unknown | uptodate | available | error
    property string remoteSha: ""
    property string localSha: ""
    property string repoOwner: ""            // screen allowed to show the dialog
    property bool repoChecking: false
    property string repoApply: ""            // "" | running | done | failed
    property int _applyPolls: 0

    readonly property bool repoUpdateAvailable:
        repoState === "available" && remoteSha !== ""
        && remoteSha !== String(Settings.get("updates.dismissedSha", ""))
    readonly property bool repoPopupOpen:
        repoUpdateAvailable || repoApply === "running" || repoApply === "failed"

    readonly property string repoStatusText: {
        if (repoApply === "running") return "Updating…"
        if (repoChecking) return "Checking…"
        switch (repoState) {
        case "available": return "Update available"
        case "uptodate":  return "Up to date"
        case "error":     return "Can't reach GitHub"
        default:          return "Not checked yet"
        }
    }

    onRepoPopupOpenChanged: {
        if (repoPopupOpen) {
            // same single-owner rule as the picker: the focused screen
            // records itself, every other screen's window stays hidden —
            // two Exclusive surfaces would fight over keyboard focus.
            const fm = Hyprland.focusedMonitor
            repoOwner = fm ? fm.name
                : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
        }
    }
    onRepoApplyChanged: _applyPolls = 0

    function checkRepo() {
        if (!repoCheck.running) repoCheck.running = true
    }

    function applyRepo() {
        if (repoState !== "available" || repoApply === "running") return
        repoApply = "running"
        // detached: the pull rewrites the config dir and quickshell reloads
        // mid-flight — an attached Process would be killed in the merge.
        // The script reports progress via its one-word state file.
        Quickshell.execDetached(["bash",
            Quickshell.shellDir + "/scripts/repo-update.sh"])
    }

    function later() {
        if (repoApply === "running") return    // let the pull finish first
        repoApply = ""
        if (remoteSha !== "") Settings.set("updates.dismissedSha", remoteSha)
    }

    // stdout contract of scripts/repo-check.sh — one line, see its header
    function _applyCheck(out) {
        const line = out.split("\n").map(s => s.trim()).filter(s => s !== "")[0] || ""
        const p = line.split(" ")
        if (p[0] === "uptodate") {
            repoState = "uptodate"; localSha = p[1] || ""; remoteSha = p[1] || ""
        } else if (p[0] === "available") {
            repoState = "available"; remoteSha = p[1] || ""; localSha = p[2] || ""
        } else {
            // one flaky probe (GitHub stalls occasionally) must not hide
            // an update already found or drop the shas we know: keep the
            // last good answer, only report "error" when there never was
            // one — a machine that boots offline still says so, and the
            // next tick retries either way.
            if (localSha === "") repoState = "error"
        }
    }

    Process {
        id: repoCheck
        command: ["bash", Quickshell.shellDir + "/scripts/repo-check.sh"]
        property var _lines: []
        onRunningChanged: {
            if (running) {
                root.repoChecking = true
                _lines = []
            } else {
                root.repoChecking = false
                root._applyCheck(_lines.join("\n"))
            }
        }
        stdout: SplitParser {
            onRead: line => repoCheck._lines.push(line)
        }
    }

    // cheap ls-remote: at startup (triggeredOnStart) + every 10 min. An
    // offline machine or missing gh credentials lands on "error" and never
    // shows a dialog — the next tick simply tries again.
    Timer {
        interval: 600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.checkRepo()
    }

    // Poll scripts/repo-update.sh's state file while an apply runs. The
    // initial read (repoApply === "") only looks for a pull that was
    // MID-FLIGHT when the shell reloaded — stale done/failed leftovers
    // from a previous round are ignored so they can't fake a result.
    Process {
        id: applyStateRead
        // `|| true` keeps a missing state file (first run ever) out of the log
        command: ["sh", "-c",
                  "cat \"$HOME/.local/state/quickshell/repo-update.state\" 2>/dev/null || true"]
        property var _lines: []
        onRunningChanged: {
            if (running) {
                _lines = []
                return
            }
            const s = _lines.join("").trim()
            if (root.repoApply === "") {
                if (s === "running") root.repoApply = "running"
            } else if (root.repoApply === "running") {
                if (s === "done") {
                    root.repoApply = "done"
                    root.checkRepo()   // pull landed — the next check closes the popup
                    Quickshell.execDetached(["notify-send", "Desktop updated",
                        "The new version is in place and the shell reloaded."])
                } else if (s === "failed") {
                    root.repoApply = "failed"
                }
            }
        }
        stdout: SplitParser {
            onRead: line => applyStateRead._lines.push(line)
        }
    }

    Timer {
        interval: 1200
        repeat: true
        running: root.repoApply === "running"
        onTriggered: {
            root._applyPolls++
            if (root._applyPolls > 600) { root.repoApply = "failed"; return }
            applyStateRead.running = false
            applyStateRead.running = true
        }
    }

    Component.onCompleted: applyStateRead.running = true   // resume a mid-pull

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
        function check(): void { root.refresh(); root.checkRepo() }
        function apply(): void { root.applyRepo() }
        function upgrade(): void { root.upgradeAll() }
        function dismiss(): void { root.later() }
        // one-line machine-readable state — used by tests and scripts
        function status(): string {
            return [root.repoState, root.repoUpdateAvailable, root.repoApply,
                    root.remoteSha, root.localSha].join("|")
        }
    }
}
