pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// The idle screensaver (manual/13-toggles-idle-screensaver.md), two
// styles behind one service, after 150 s of no input by default:
//   flip  — FlipClock.qml in THIS process (default): a Fliqlo-style
//           split-flap clock, static between minute flips, ~0 CPU at rest
//   pipes — the original omarchy path: a terminal per monitor running
//           pipes.sh (~0.9 of a core while it runs), runner in
//           ~/.local/bin/omarchy-launch-screensaver
// This singleton owns the two triggers omarchy has — idle, and
// on-demand — plus the style switch and the on/off flag behind the
// Control Center's Screen Saver tile.
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
    // Pipes style only — the flip clock never leaves this process.
    readonly property string launcher: Quickshell.env("HOME") + "/.local/bin/omarchy-launch-screensaver"

    // omarchy's on/off flag — the same file `omarchy toggle screensaver`
    // writes; the launcher refuses while it exists. In-memory mirror so
    // the Control Center tile has a bindable state: seeded from disk by
    // the probe below, then this service is the only writer.
    readonly property string flagDir: Quickshell.env("HOME") + "/.local/state/omarchy/toggles"
    readonly property string flagFile: flagDir + "/screensaver-off"
    property bool enabled: true

    // ————— style —————
    // screensaver.style ("Flip clock" / "Pipes terminal" in Settings ▸
    // Lock screen). Both branches share every gate in this file;
    // startSaver() below is where the split happens.
    readonly property bool styleFlip: Settings.screensaverStyle === "flip"

    // ————— what's on screen —————
    // `active` is what Bar.qml gates the bar's visibility on: the bar is
    // a layer-shell surface and layer-shell ALWAYS paints above normal
    // windows, so without this the bar sits visibly over any fullscreen
    // saver. Session-only state, same as shell.qml's barVisible.
    // It is DERIVED, never written: runnerActive is the pipes runner's
    // own report (`qs ipc call screensaver started|stopped` — started
    // after its setup, stopped first thing in its exit trap, so the
    // pair survives every normal exit path); internalActive is the flip
    // clock's. Two independent writers feeding an OR means a double
    // dismiss or a mid-run style switch can never leave the bar
    // unmapped with nothing on screen, nor a saver up under the bar.
    property bool runnerActive: false
    property bool internalActive: false
    readonly property bool active: runnerActive || internalActive

    // ————— flip clock surface control —————
    // FlipClock.qml binds its windows' visible on internalActive and
    // calls dismiss() for input on its own surfaces; every other path
    // (the ext-idle reset, IPC stop, toggle-off, the lock chain) routes
    // through these two so the cursor and the bar gate always move
    // together with the surface.

    // cursor hiding — the same hyprctl eval the pipes runner uses: a
    // quickshell surface can only ask the compositor. The unconditional
    // restore at startup is the hot-reload guard — if quickshell
    // reloads WHILE the clock is up, this singleton re-creates with
    // internalActive false and nothing else would ever run the restore
    // half of the pair (the cursor would stay invisible on the desktop).
    function setCursorHidden(hide: bool): void {
        const v = hide ? "true" : "false"
        Quickshell.execDetached(["sh", "-c",
            "hyprctl eval 'hl.config({ cursor = { invisible = " + v + " } })' >/dev/null 2>&1 || " +
            "hyprctl keyword cursor:invisible " + v + " >/dev/null 2>&1 || true"])
    }
    Component.onCompleted: setCursorHidden(false)

    function showInternal(): void {
        // ext-session-lock surfaces always render above us — a clock
        // started now would only pop out after the unlock, mid-auth.
        // (The pipes branch gets the equivalent for free: beginLock
        // kills its runners.)
        if (root.sessionLocked) return
        if (root.internalActive) return
        root.internalActive = true
        root.setCursorHidden(true)
    }
    function dismiss(): void {
        if (!root.internalActive) return
        root.internalActive = false
        root.setCursorHidden(false)
    }

    // Every "put the saver on screen" path funnels here — the idle
    // trigger, `qs ipc call screensaver launch|force`, the CC tile's
    // right click. Each branch clears the other's surface first, so
    // two savers can never share the screen even across a mid-run
    // style switch.
    function startSaver(force: bool): void {
        if (!force && !root.enabled) return
        if (root.styleFlip) {
            root.stopRunner()
            root.showInternal()
        } else {
            root.dismiss()
            Quickshell.execDetached(force ? [root.launcher, "force"] : [root.launcher])
        }
    }

    // one-shot exit-code probe (`test -e` → 0 = flag present = saver off)
    Process {
        command: ["test", "-e", root.flagFile]
        running: true
        onExited: (code) => { root.enabled = code !== 0 }
    }

    // Off sets the flag AND kills a saver that's already running —
    // whichever style is up (flip clock or pipes terminals, the CPU
    // load this tile exists to silence) — on clears the flag so the
    // idle trigger may fire again.
    function toggle() {
        root.enabled = !root.enabled
        if (root.enabled) {
            Quickshell.execDetached(["rm", "-f", root.flagFile])
        } else {
            Quickshell.execDetached(["sh", "-c",
                "mkdir -p \"$HOME/.local/state/omarchy/toggles\" && touch \"$HOME/.local/state/omarchy/toggles/screensaver-off\""])
            root.dismiss()
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
    // The lock replaces the saver in the chain (beginLock kills the
    // runner too): unmap the flip clock at the same moment — left up,
    // it would sit invisible under the lock surfaces and pop back out
    // after the unlock with no idle edge left to dismiss it on.
    onSessionLockedChanged: if (sessionLocked) root.dismiss()

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
                root.startSaver(false)
            else if (!isIdle && root.internalActive)
                // ANY input resets ext-idle — this is the flip clock's
                // "any key dismisses", global even when the press
                // landed on a surface that wasn't ours. A manually
                // launched clock never gets a true→false edge to ride
                // (it starts with isIdle false) — that's what its own
                // key/pointer handlers in FlipClock.qml are for.
                root.dismiss()
        }
    }

    IpcHandler {
        target: "screensaver"
        // runner lifecycle reports — see runnerActive above; Bar.qml
        // binds on the derived `active`
        function started(): void { root.runnerActive = true }
        function stopped(): void { root.runnerActive = false }
        // on demand, honoring omarchy's screensaver-off flag file —
        // the style decides which surface appears. Returns the gate
        // state so a no-op says WHICH gate said no.
        function launch(): string {
            const pre = `en=${root.enabled} flip=${root.styleFlip}` +
                ` locked=${root.sessionLocked} internal=${root.internalActive}`
            root.startSaver(false)
            return pre + ` -> internal=${root.internalActive}` +
                ` active=${root.active}`
        }
        // past the flag — omarchy's System > Screensaver action, and
        // the Control Center tile's right click
        function force() { root.startSaver(true) }
        // dismiss the flip clock AND kill the runner (its trap restores
        // the terminal's cursor and closes the terminal)
        function stop() { root.dismiss(); root.stopRunner() }
        // Control Center tile: on/off (flag + whatever is running), state probe
        function toggle(): void { root.toggle() }
        function status(): bool { return root.enabled }
        function idle(): string {
            return JSON.stringify({
                saverEnabled: saverIdle.enabled,
                saverTimeout: saverIdle.timeout,
                saverIsIdle: saverIdle.isIdle,
                idleSeconds: root.idleSeconds,
                active: root.active,
                style: root.styleFlip ? "flip" : "pipes",
                internal: root.internalActive,
                locked: root.sessionLocked
            })
        }
    }
}
