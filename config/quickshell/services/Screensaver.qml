pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Omarchy's idle screensaver, ported (manual/13-toggles-idle-screensaver.md):
// ASCII art through random ttfx effects in the default terminal after 150 s
// of no input. The heavy lifting lives in ~/.local/bin/omarchy-launch-screensaver;
// this singleton owns the two triggers omarchy has — idle, and on-demand —
// plus the on/off flag behind the Control Center's Screen Saver tile.
Singleton {
    id: root

    // omarchy's default from shell.json ("idle": { "screensaver": 150 }),
    // live: the settings app's "Screensaver after" chips write the same
    // file through scripts/set-idle.sh and this watch re-arms the
    // IdleMonitor below — no shell restart to move the timeout.
    property int idleSeconds: 150
    // async-load gate + recreation switch for saverIdle — same two as
    // LockScreen.qml (idleLoaded/idleArmed): without the gate the
    // notification is registered at construction with the 150 s default
    // and quickshell never applies the shell.json value afterwards.
    property bool idleLoaded: false
    property bool saverArmed: true

    FileView {
        path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const v = JSON.parse(text()).idle.screensaver
                if (typeof v === "number" && v > 0)
                    root.idleSeconds = v
            } catch (e) {
                console.log("Screensaver: shell.json parse", e)
            }
            // after the value, never before — see saverArmed
            root.idleLoaded = true
        }
        onLoadFailed: root.idleLoaded = true
    }

    // ~/.local/bin is deliberately not on PATH in this setup (.bashrc), so
    // everything here is addressed by absolute path rather than by name.
    readonly property string launcher: Quickshell.env("HOME") + "/.local/bin/omarchy-launch-screensaver"

    // omarchy's on/off flag — the same file `omarchy toggle screensaver`
    // writes; the launcher refuses while it exists. In-memory mirror so
    // the Control Center tile has a bindable state: seeded from disk by
    // the probe below, then this service is the only writer.
    readonly property string flagDir: Quickshell.env("HOME") + "/.local/state/omarchy/toggles"
    readonly property string flagFile: flagDir + "/screensaver-off"
    property bool enabled: true

    // one-shot exit-code probe (`test -e` → 0 = flag present = saver off)
    Process {
        command: ["test", "-e", root.flagFile]
        running: true
        onExited: (code) => { root.enabled = code !== 0 }
    }

    // Off sets the flag AND kills a saver that's already running — the
    // pipes.sh terminals are the CPU/RAM load this tile exists to
    // silence — on clears the flag so the idle trigger may fire again.
    function toggle() {
        root.enabled = !root.enabled
        if (root.enabled) {
            Quickshell.execDetached(["rm", "-f", root.flagFile])
        } else {
            Quickshell.execDetached(["sh", "-c",
                "mkdir -p \"$HOME/.local/state/omarchy/toggles\" && touch \"$HOME/.local/state/omarchy/toggles/screensaver-off\""])
            root.stopRunner()
        }
    }

    function stopRunner() {
        Quickshell.execDetached(["pkill", "-f", "[o]marchy-screensaver"])
    }

    // Re-create the wayland notification so its countdown starts over —
    // a fresh ext_idle_notification begins its timer at creation. The
    // lock screen's watchdog calls this when it spots a resume from
    // suspend: idle deadlines that expired while the machine was frozen
    // must not fire the instant it wakes (the hypridle #73 re-sleep bug).
    // Two event-loop turns, or quickshell coalesces the flip and
    // re-creates nothing (see LockScreen.qml idleArmed).
    Timer {
        id: saverRearmTimer
        interval: 50
        onTriggered: root.saverArmed = true
    }

    function rearmIdle() {
        if (root.saverArmed) {
            root.saverArmed = false
            saverRearmTimer.restart()
        }
    }

    // The lock screen pushes its state here (its Binding writes this —
    // a singleton can't see the root item, so state flows one way).
    // Idle launches stay quiet once the session is locked: the lock
    // surface already owns the screen, and a late timer (a "Lock after"
    // chip shorter than "Screensaver after", or wake-expired timers)
    // must not spawn pipes.sh terminals behind it. The manual paths —
    // qs ipc call screensaver launch|force, the Control Center tile —
    // deliberately ignore this.
    property bool sessionLocked: false

    // ext-idle-notify-v1 — the same protocol hypridle listens on. Defaults
    // respect idle inhibitors (fullscreen video, etc.) and re-arm after
    // input, and the saver exiting on first input is handled inside the
    // runner itself, so no onResumed work is needed here.
    IdleMonitor {
        id: saverIdle
        timeout: root.idleSeconds
        enabled: root.saverArmed && root.idleLoaded
        // chip edits go through FileView → idleSeconds: quickshell won't
        // move a live notification's timeout, so re-create it instead
        onTimeoutChanged: if (enabled) root.rearmIdle()
        onIsIdleChanged: {
            // KeepAwake (Control Center tile) refuses the saver while
            // it's armed — belt one; belt two is the Wayland
            // idle-inhibit surface KeepAwake itself advertises, which
            // keeps hypridle and friends quiet too. The screensaver
            // tile's own off flag is belt three: don't even fork the
            // launcher when the saver is switched off. Belt four is the
            // session lock: the chain is saver → lock → sleep, and past
            // the lock step there is no saver anymore.
            if (isIdle && !KeepAwake.active && root.enabled && !root.sessionLocked)
                Quickshell.execDetached([root.launcher])
        }
    }

    IpcHandler {
        target: "screensaver"
        // on demand, honoring omarchy's screensaver-off flag file
        function launch() { Quickshell.execDetached([root.launcher]) }
        // past the flag — omarchy's System > Screensaver action
        function force() { Quickshell.execDetached([root.launcher, "force"]) }
        // kill the runner; its trap restores the cursor, stops ttfx and
        // closes the terminal
        function stop() { root.stopRunner() }
        // Control Center tile: on/off (flag + live runner), state probe
        function toggle(): void { root.toggle() }
        function status(): bool { return root.enabled }
        function idle(): string {
            return JSON.stringify({
                saverEnabled: saverIdle.enabled,
                saverTimeout: saverIdle.timeout,
                saverIsIdle: saverIdle.isIdle,
                idleSeconds: root.idleSeconds
            })
        }
    }
}
