import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Io
import "./lock" as Lock
import "./services" as Services

// quickshell-native lock screen — replaces hyprlock entirely.
//
// Uses the real ext-session-lock protocol: WlSessionLock creates one
// WlSessionLockSurface per screen and the compositor itself guarantees
// nothing renders above it and input goes nowhere else — a genuine lock,
// not a fullscreen overlay. Auth runs through PAM service "qs-lock"
// (/etc/pam.d/qs-lock, one-time setup: ~/.local/bin/qs-lock-pam).
//
// Adapted from omarchy's shell/plugins/lock (Service.qml), trimmed to
// password-only v1: fingerprint / idle-blank deferred.
//
// The layout is NOT in here: lock/ holds five styles (Classic, Card,
// Minimal, Magazine, Clock), lock.style in settings.json picks one and the
// Loader below draws it. This file owns the session lock, PAM and the
// auth state every style reads — see lock/Classic.qml for the shape of
// the contract: property lock + function focusField().
//
// FAILSAFE: never engages the lock unless /etc/pam.d/qs-lock is known to
// exist — locking into a state that can't authenticate would strand the
// session (TTY recovery only). Missing file → hyprctl notify instead.
//
// ⚠ quickshell hot-reloads QML on save: editing files while locked
// destroys the lock client mid-session. hyprland keeps the lock when the
// client dies, so the stranded-lock check below re-engages it on start.
Item {
    id: root

    // non-visual host: 0×0. The visible parts are the lock surfaces
    // created per-screen by WlSessionLock below.
    visible: false

    readonly property bool locked: lockRequested || sessionLock.locked || sessionLock.secure
    readonly property string userName: Quickshell.env("USER") || Quickshell.env("LOGNAME")

    property bool lockRequested: false
    property bool passwordPamConfigured: false
    property bool authenticatingPassword: false
    property string enteredPassword: ""
    property string pendingPassword: ""
    property string failureMessage: ""
    property int failedAttempts: 0

    // ——————— idle chain (shell.json "idle": { lock, sleep }) ———————
    // Stage two of three: screensaver (services/Screensaver.qml) →
    // lock (below) → suspend. The settings app's chips write the keys
    // through scripts/set-idle.sh; the watch below re-arms the monitors
    // live. Every stage has its own timeout and skips independently —
    // screensaver off just drops its step, lock still fires at
    // "Lock after" (stage three re-checks the lock itself, so the order
    // holds even if the chips are configured out of order). All stages
    // stay quiet while KeepAwake asked the session to stay up (same
    // belt order everywhere), and the same beginLock() path Super+L
    // takes — never while the session is already locked.
    property int idleLockSeconds: 300
    // Stage three, the suspend step: 0 = the "Never" chip, which stops
    // the monitor and the watchdog below entirely.
    property int idleSleepSeconds: 1800
    // wall ms until a refused `systemctl suspend` may be retried
    property double sleepBackoffUntil: 0
    // awakeClock reading of the last observed input (0 = shell start —
    // the clock starts there too)
    property double lastActivityMs: 0
    // armed = the monitors exist and count. Flipping this false→true is
    // how rearmIdle() re-creates them; it is a separate property because
    // assigning to `enabled` directly would shatter the bindings the
    // monitors declare on it. The flip must be SPLIT across two
    // event-loop turns (rearmTimer below): a synchronous false→true is
    // coalesced by quickshell into a no-op and never touches the wire,
    // while a persisted false destroys the ext_idle_notification and the
    // later true re-creates it with the current timeout.
    property bool idleArmed: true
    // FileView loads async, but quickshell registers each IdleMonitor's
    // Wayland notification at construction with whatever `timeout` reads
    // then — and NEVER applies later timeout changes (proven on the
    // wire: no destroy, no re-request). So the monitors must stay
    // disabled until shell.json has been applied, or they'd count with
    // the QML defaults (300 s / 1800 s) forever.
    property bool idleLoaded: false

    FileView {
        path: Quickshell.env("HOME") + "/.config/omarchy/shell.json"
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const d = JSON.parse(text()).idle
                if (typeof d.lock === "number" && d.lock > 0)
                    root.idleLockSeconds = d.lock
                // >= 0: sleep alone accepts 0, it is the "Never" chip
                if (typeof d.sleep === "number" && d.sleep >= 0)
                    root.idleSleepSeconds = d.sleep
            } catch (e) {
                console.log("Lock: shell.json parse", e)
            }
            // after the values, never before: the monitors arm on this
            root.idleLoaded = true
        }
        // unreadable file → keep the QML defaults and arm anyway; a
        // broken config must degrade to the default chain, not kill it
        onLoadFailed: root.idleLoaded = true
    }

    IdleMonitor {
        id: lockIdle
        timeout: root.idleLockSeconds
        enabled: root.idleArmed && root.idleLoaded
        // quickshell ignores timeout changes on a live notification —
        // this recreate is what makes a chip edit take effect on the wire
        onTimeoutChanged: if (enabled) root.rearmIdle()
        onIsIdleChanged: {
            if (isIdle && !root.locked && !Services.KeepAwake.active)
                root.beginLock()
        }
    }

    // ——————— idle suspend (stage three) ———————
    // QElapsedTimer is CLOCK_MONOTONIC, which freezes while the system
    // is suspended — this is the awake-time clock every "idle long
    // enough?" check below runs against. Wall time jumps across a nap,
    // this doesn't, which is what defuses the known Hyprland/hypridle
    // wake bug (hypridle#73): idle deadlines that expire during suspend
    // fire the instant the machine resumes, and a naive sleep stage
    // would lock-and-re-sleep it before you can type. Here that wake
    // reads ~0 s of awake-idle and is refused; the watchdog restarts
    // every countdown from the moment of wake instead.
    ElapsedTimer { id: awakeClock }

    // Fresh countdown for both monitors: a fresh ext_idle_notification
    // starts its timer at creation. The false→true must span two event
    // loop turns (see idleArmed above) or quickshell coalesces it into a
    // no-op and nothing is re-created at all.
    Timer {
        id: rearmTimer
        interval: 50
        onTriggered: root.idleArmed = true
    }

    function rearmIdle() {
        if (root.idleArmed) {
            root.idleArmed = false
            rearmTimer.restart()
        }
        Services.Screensaver.rearmIdle()
    }

    IdleMonitor {
        id: sleepIdle
        // timeout must be positive; the enabled flag below is what
        // "Never" turns off, the value never reaches 0 while enabled
        timeout: Math.max(root.idleSleepSeconds, 1)
        enabled: root.idleSleepSeconds > 0 && root.idleArmed && root.idleLoaded
        onTimeoutChanged: if (enabled) root.rearmIdle()
        onIsIdleChanged: {
            if (isIdle) root.trySleep()
            else root.lastActivityMs = awakeClock.elapsedMs()
        }
    }

    // Every gate is re-checked on each call — the watchdog poll below
    // invokes this at arbitrary times, not only at the exact timeout.
    function trySleep() {
        if (root.idleSleepSeconds <= 0) return            // "Never" chip
        if (Services.KeepAwake.active) return
        if (!sleepIdle.isIdle) return                     // fresh input, or a Wayland
                                                          // idle inhibitor (video)
        if (Date.now() < root.sleepBackoffUntil) return   // suspend refused recently
        // Awake-idle, not wall-idle (see awakeClock above). The 5 s
        // slack absorbs the event round-trip: our input timestamp lands
        // a hair after the compositor's, so the exact-timeout event can
        // read microseconds short of the target.
        if (awakeClock.elapsedMs() - root.lastActivityMs + 5000 < root.idleSleepSeconds * 1000)
            return
        // Ordering + safety: never sleep an unlocked session. Lock not
        // engaged yet → engage it now (beginLock() refuses without
        // /etc/pam.d/qs-lock and drags us down with it — an unlocked
        // machine must stay awake).
        if (!root.locked && !root.beginLock()) return
        sleepGrace.running = true
    }

    // One beat before freezing userspace so the session-lock surface has
    // time to map over whatever was on screen. Re-checked when it lands:
    // input may have arrived during the grace.
    Timer {
        id: sleepGrace
        interval: 1000
        onTriggered: {
            if (!sleepIdle.isIdle || Services.KeepAwake.active) return
            if (!root.locked) return
            suspendProc.running = true
        }
    }

    Process {
        id: suspendProc
        command: ["systemctl", "suspend"]
        onExited: (code) => {
            // polkit denial, an active sleep inhibitor (fwupd, apt…) …
            if (code !== 0) {
                root.sleepBackoffUntil = Date.now() + 120000
                notifySuspendFailed.running = true
            }
        }
    }

    Process {
        id: notifySuspendFailed
        command: ["hyprctl", "notify", "3", "6000", "rgba(ffcc66ee)",
                  "Idle sleep failed (systemctl suspend) — will retry in 2 min"]
    }

    // Wake watchdog + sleep safety net — one 15 s tick while the sleep
    // stage is configured. Two jobs:
    //  1. Resume detection: the wall clock jumps across a suspend, the
    //     awakeClock does not — a jump well past the interval means we
    //     just woke. Then reset the awake-idle baseline, re-arm all
    //     three monitors (countdowns restart from wake instead of
    //     firing on deadlines that expired while frozen) and lock if
    //     the machine slept unlocked (lid closed mid-work: the
    //     before-sleep lock, delivered late but at wake).
    //  2. Retry net: a monitor can sit isIdle=true across a suspend
    //     with no new event for trySleep() to react to.
    property double lastWallAt: 0
    Timer {
        interval: 15000
        repeat: true
        running: root.idleSleepSeconds > 0
        onTriggered: {
            const wall = Date.now()
            // >20 s between 15 s ticks = ≥5 s of suspend (the wall clock
            // walked while the monotonic Qt timer didn't; NTP is not
            // running on this box, so nothing else moves the wall this
            // far) — even a short nap must restart every countdown, or
            // the stale isIdle sails into trySleep() at the first tick
            // after wake (hypridle #73 with a short nap).
            if (root.lastWallAt !== 0 && wall - root.lastWallAt > interval + 5000) {
                root.lastActivityMs = awakeClock.elapsedMs()
                root.rearmIdle()
                if (!root.locked) root.beginLock()
            }
            root.lastWallAt = wall
            root.trySleep()
        }
    }

    // The screensaver singleton can't see this root item, so the lock
    // state travels to it — see Screensaver.sessionLocked: past the
    // lock step of the chain the saver stays quiet.
    Binding {
        target: Services.Screensaver
        property: "sessionLocked"
        value: root.locked
    }

    // ——————— which layout is on show ———————
    // lock.style in settings.json — written by the preview row on
    // Settings ▸ Lock screen, read live, so the next lock picks the new
    // style up with no reload. Unknown values fall back to classic:
    // locking into a blank surface is the one failure this must not have.
    readonly property var styleComponent: {
        switch (Services.Settings.lockStyle) {
        case "card":     return compCard
        case "minimal":  return compMinimal
        case "magazine": return compMagazine
        case "clock":    return compClock
        default:         return compClassic
        }
    }

    Component { id: compClassic;  Lock.Classic  { lock: root } }
    Component { id: compCard;     Lock.Card     { lock: root } }
    Component { id: compMinimal;  Lock.Minimal  { lock: root } }
    Component { id: compMagazine; Lock.Magazine { lock: root } }
    Component { id: compClock;    Lock.Clock    { lock: root } }

    // one clock for every style — the date line and the settings preview
    // both read it through `lock.now`
    SystemClock { id: nowClock; precision: SystemClock.Minutes }
    readonly property date now: nowClock.date

    // Styles move the field, so its id lives inside the Loader — and
    // because WlSessionLockSurface instantiates its children in a
    // per-output component scope, that id is NOT visible from root scope
    // (a bare `styleLoader` here throws ReferenceError at runtime). The
    // Loader registers itself below; every focus request funnels through
    // the loaded component's focusField() instead.
    property var styleLoaderRef: null

    function focusPassword() {
        if (styleLoaderRef && styleLoaderRef.item && styleLoaderRef.item.focusField)
            styleLoaderRef.item.focusField()
    }

    function logEvent(event) {
        console.log("qs-lock " + new Date().toISOString() + " " + event)
    }

    function resetAuthenticationState() {
        enteredPassword = ""
        pendingPassword = ""
        failureMessage = ""
        failedAttempts = 0
        authenticatingPassword = false
        if (passwordPam.active) passwordPam.abort()
    }

    function beginLock() {
        if (!passwordPamConfigured) {
            logEvent("lock-denied: missing-pam")
            notifyMissingPam.running = true
            return false
        }

        resetAuthenticationState()
        lockRequested = true
        logEvent("lock-requested")
        sessionLock.locked = true
        // The lock replaces the screensaver in the idle chain: kill the
        // pipes.sh runners so they don't keep burning CPU behind the
        // lock surface — their input loop can never see the keystrokes
        // now (they go to the lock), so nothing else would stop them.
        Services.Screensaver.stopRunner()
        return true
    }

    function finishUnlock() {
        if (!lockRequested && !sessionLock.locked) return

        lockRequested = false
        resetAuthenticationState()
        sessionLock.locked = false
        logEvent("unlocked")
    }

    function submitPassword(value) {
        var password = String(value || "")
        if (!lockRequested || authenticatingPassword || password.length === 0) return

        pendingPassword = password
        failureMessage = ""
        authenticatingPassword = true

        if (!passwordPam.start()) {
            handlePasswordFailure()
            return
        }

        Qt.callLater(respondToPasswordPrompt)
    }

    function respondToPasswordPrompt() {
        if (!authenticatingPassword || !passwordPam.active || !passwordPam.responseRequired) return
        passwordPam.respond(pendingPassword)
    }

    function handlePasswordFailure() {
        if (!lockRequested) return

        authenticatingPassword = false
        enteredPassword = ""
        pendingPassword = ""
        failedAttempts += 1
        failureMessage = "Authentication failed (" + failedAttempts + ")"
        Qt.callLater(root.focusPassword)
    }

    WlSessionLock {
        id: sessionLock
        locked: false

        onLockStateChanged: {
            root.logEvent("session-locked=" + locked)

            if (locked) {
                Qt.callLater(root.focusPassword)
            } else if (root.lockRequested) {
                // compositor dropped the lock under us — resync instead of
                // leaving lockRequested stuck true
                root.lockRequested = false
                root.resetAuthenticationState()
            }
        }

        WlSessionLockSurface {
            id: lockSurface
            // shows through while the wallpaper decodes, and is the whole
            // backdrop if there is no wallpaper set at all
            color: Services.Colors.background

            onVisibleChanged: {
                if (visible) Qt.callLater(root.focusPassword)
            }

            // The chosen style draws the backdrop AND its layout; the
            // surface only supplies the canvas (and the fallback colour
            // while the wallpaper decodes). Focus requests reach the
            // field inside the component through root.focusPassword().
            Loader {
                id: styleLoader
                anchors.fill: parent
                sourceComponent: root.styleComponent
                onLoaded: if (item && root.lockRequested) Qt.callLater(item.focusField)
                // hand root a scope-safe handle (see styleLoaderRef)
                Component.onCompleted: root.styleLoaderRef = styleLoader
                Component.onDestruction: if (root.styleLoaderRef === styleLoader)
                    root.styleLoaderRef = null
            }

        }
    }

    PamContext {
        id: passwordPam
        config: "qs-lock"
        user: root.userName

        onResponseRequiredChanged: root.respondToPasswordPrompt()
        onPamMessage: root.respondToPasswordPrompt()

        onCompleted: function(result) {
            root.authenticatingPassword = false
            root.pendingPassword = ""
            if (!root.lockRequested) return
            if (result === PamResult.Success) root.finishUnlock()
            else root.handlePasswordFailure()
        }

        onError: function(error) {
            root.logEvent("pam-error: " + error)
            root.handlePasswordFailure()
        }
    }

    // the failsafe gate — beginLock() refuses to engage without this
    FileView {
        path: "/etc/pam.d/qs-lock"
        watchChanges: true
        printErrors: false
        onLoaded: root.passwordPamConfigured = true
        onLoadFailed: root.passwordPamConfigured = false
        onFileChanged: reload()
    }

    // hyprland keeps the session lock after the locking client dies
    // (crash, or quickshell hot-reload while locked) — no UI to unlock
    // would be left. Re-engage immediately on start. Same recovery
    // omarchy's lock plugin does with its stranded-lock check.
    Process {
        id: strandedLockCheck
        running: true
        command: ["python3", "-c",
            "import json,subprocess,sys;" +
            "m=json.loads(subprocess.run(['hyprctl','-j','monitors'],capture_output=True,text=True).stdout);" +
            "sys.exit(0 if any('LOCK' in (x.get('solitaryBlockedBy') or []) for x in m) else 1)"]
        onExited: exitCode => {
            if (exitCode === 0 && !root.locked) {
                root.logEvent("lock-stranded: recovering")
                root.beginLock()
            }
        }
    }

    Process {
        id: notifyMissingPam
        command: ["hyprctl", "notify", "3", "6000", "rgba(ff5555ee)",
                  "Lock unavailable — run qs-lock-pam to set up authentication"]
    }

    // Hyprland keybind entry point (Super+L)
    IpcHandler {
        target: "lock"

        function lock(): string {
            if (root.locked) return "already-locked"
            if (!root.beginLock()) return "missing-pam"
            return "ok"
        }

        // diagnostic: replay the watchdog's rearm path on demand
        function rearm(): string {
            root.rearmIdle()
            return "rearmed"
        }

        function status(): string {
            return JSON.stringify({
                locked: root.locked,
                requested: root.lockRequested,
                secure: sessionLock.secure,
                passwordPam: root.passwordPamConfigured,
                authenticating: root.authenticatingPassword,
                failedAttempts: root.failedAttempts,
                sleepSeconds: root.idleSleepSeconds,
                sleepIdle: sleepIdle.isIdle,
                awakeIdleSeconds: Math.round((awakeClock.elapsedMs() - root.lastActivityMs) / 1000),
                idleArmed: root.idleArmed,
                lockIdleEnabled: lockIdle.enabled,
                lockIdleTimeout: lockIdle.timeout,
                sleepIdleEnabled: sleepIdle.enabled,
                sleepIdleTimeout: sleepIdle.timeout
            })
        }
    }
}
