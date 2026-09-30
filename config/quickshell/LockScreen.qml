import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Io
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
// password-only v1: fingerprint / idle-blank / preview deferred.
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

    // The lock backdrop is the live desktop wallpaper, blurred.
    //
    // Background.qml and this file can disagree for a moment: Wallpapers
    // crossfades the desktop by layering `previous` over `current` with an
    // opacity tween, but the lock has no reason to animate — it just points
    // at whatever `current` is when the surface comes up, so a wallpaper
    // switched mid-session shows the new one on the next lock.
    function fileUrl(path) {
        if (path === "") return ""
        // encode each segment: theme dirs are user-chosen and a space in a
        // directory name would otherwise truncate the source at that byte
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
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
        Qt.callLater(function() { passwordInput.forceActiveFocus() })
    }

    WlSessionLock {
        id: sessionLock
        locked: false

        onLockStateChanged: {
            root.logEvent("session-locked=" + locked)

            if (locked) {
                Qt.callLater(function() { passwordInput.forceActiveFocus() })
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
                if (visible) Qt.callLater(function() { passwordInput.forceActiveFocus() })
            }

            Image {
                id: lockWallpaper
                anchors.fill: parent
                source: root.fileUrl(Services.Wallpapers.current)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: true
                // cap the decode at screen size — MultiEffect samples this
                // every frame the lock is up, so anything larger is waste
                sourceSize.width: width
                sourceSize.height: height
                // REQUIRED by QtQuick.Effects: MultiEffect draws a second,
                // separate item *alongside* its source rather than
                // replacing it. With both visible the sharp image sits under
                // the blur and shows through wherever the blur samples past
                // the edge of the surface.
                visible: false
            }

            // Blur parameters mirror omarchy's plugins/lock/LockView.qml —
            // the screen this file was adapted from. autoPaddingEnabled MUST
            // be false here: Qt's own guidance is that with it on, a
            // full-screen blur "grows outside the window / screen".
            // blurMultiplier rather than a bigger blurMax, per the same
            // performance note (bigger blurMax costs texture lookups).
            MultiEffect {
                anchors.fill: parent
                source: lockWallpaper
                autoPaddingEnabled: false
                // gate on Ready so the shader isn't sized against an image
                // that hasn't decoded yet
                blurEnabled: lockWallpaper.status === Image.Ready
                blur: 1.0
                blurMax: 128
                blurMultiplier: 1.25
                contrast: -0.08
            }

            // Scrim: the clock is 150px in Colors.text and the field label
            // is 13px, both straight over the wallpaper. A blurred bright
            // image would otherwise put light-on-light behind them. Themed
            // background rather than plain black so it tints to the palette
            // instead of greying the wallpaper out.
            Rectangle {
                anchors.fill: parent
                color: Services.Colors.background
                opacity: 0.4
            }

            // click anywhere to (re)focus the field
            MouseArea {
                anchors.fill: parent
                onClicked: passwordInput.forceActiveFocus()
            }

            Column {
                anchors.centerIn: parent
                width: 460
                spacing: 10

                Text {
                    font.family: Services.Fonts.family
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Services.Time.time
                    font.pixelSize: 150
                    font.weight: Font.Bold
                    color: Services.Colors.text
                }

                Text {
                    font.family: Services.Fonts.family
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDateTime(nowClock.date, "dddd, MMMM d")
                    font.pixelSize: 15
                    color: Services.Colors.textMuted
                }

                Item { width: 1; height: 44 }   // spacer

                Text {
                    font.family: Services.Fonts.family
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: root.userName
                    font.pixelSize: 13
                    color: Services.Colors.textMuted
                }

                Rectangle {
                    id: field
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    height: 48
                    radius: 12
                    color: Services.Colors.surface
                    border.width: 1
                    border.color: root.failureMessage.length > 0 ? Services.Colors.critical
                                : passwordInput.activeFocus ? Services.Colors.accent
                                : Services.Colors.low
                    Behavior on border.color { ColorAnimation { duration: Services.Motion.short3; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.standardCurve } }

                    TextInput {
                        font.family: Services.Fonts.family
                        id: passwordInput
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        verticalAlignment: TextInput.AlignVCenter
                        color: Services.Colors.text
                        selectionColor: Services.Colors.accent
                        selectedTextColor: Services.Colors.background
                        font.pixelSize: 15
                        echoMode: TextInput.Password
                        passwordCharacter: "●"
                        enabled: root.lockRequested && !root.authenticatingPassword
                        focus: root.lockRequested

                        onAccepted: {
                            root.submitPassword(text)
                            text = ""
                        }
                        Keys.onEscapePressed: {
                            text = ""
                            root.failureMessage = ""
                        }
                    }

                    Text {
                        font.family: Services.Fonts.family
                        visible: passwordInput.text.length === 0 && !root.authenticatingPassword
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                        text: "Password"
                        font.pixelSize: 15
                        color: Services.Colors.textMuted
                    }
                }

                Text {
                    font.family: Services.Fonts.family
                    id: statusText
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: parent.width
                    height: 18
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: 13
                    text: root.authenticatingPassword ? "Checking…" : root.failureMessage
                    color: root.failureMessage.length > 0 ? Services.Colors.critical : Services.Colors.textMuted
                    opacity: text.length > 0 ? 1 : 0
                    Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }
                }
            }

            SystemClock {
                id: nowClock
                precision: SystemClock.Minutes
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
