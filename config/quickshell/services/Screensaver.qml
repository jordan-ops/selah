pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// Omarchy's idle screensaver, ported (manual/13-toggles-idle-screensaver.md):
// ASCII art through random ttfx effects in the default terminal after 150 s
// of no input. The heavy lifting lives in ~/.local/bin/omarchy-launch-screensaver;
// this singleton owns the two triggers omarchy has — idle, and on-demand.
Singleton {
    id: root

    // omarchy's default from shell.json ("idle": { "screensaver": 150 })
    readonly property int idleSeconds: 150

    // ~/.local/bin is deliberately not on PATH in this setup (.bashrc), so
    // everything here is addressed by absolute path rather than by name.
    readonly property string launcher: Quickshell.env("HOME") + "/.local/bin/omarchy-launch-screensaver"

    // ext-idle-notify-v1 — the same protocol hypridle listens on. Defaults
    // respect idle inhibitors (fullscreen video, etc.) and re-arm after
    // input, and the saver exiting on first input is handled inside the
    // runner itself, so no onResumed work is needed here.
    IdleMonitor {
        timeout: root.idleSeconds
        onIsIdleChanged: {
            if (isIdle)
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
        function stop() { Quickshell.execDetached(["pkill", "-f", "[o]marchy-screensaver"]) }
    }
}
