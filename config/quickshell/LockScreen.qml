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

        function status(): string {
            return JSON.stringify({
                locked: root.locked,
                requested: root.lockRequested,
                secure: sessionLock.secure,
                passwordPam: root.passwordPamConfigured,
                authenticating: root.authenticatingPassword,
                failedAttempts: root.failedAttempts
            })
        }
    }
}
