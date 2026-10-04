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

    // omarchy's default from shell.json ("idle": { "screensaver": 150 })
    readonly property int idleSeconds: 150

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

    // ext-idle-notify-v1 — the same protocol hypridle listens on. Defaults
    // respect idle inhibitors (fullscreen video, etc.) and re-arm after
    // input, and the saver exiting on first input is handled inside the
    // runner itself, so no onResumed work is needed here.
    IdleMonitor {
        timeout: root.idleSeconds
        onIsIdleChanged: {
            // KeepAwake (Control Center tile) refuses the saver while
            // it's armed — belt one; belt two is the Wayland
            // idle-inhibit surface KeepAwake itself advertises, which
            // keeps hypridle and friends quiet too. The screensaver
            // tile's own off flag is belt three: don't even fork the
            // launcher when the saver is switched off.
            if (isIdle && !KeepAwake.active && root.enabled)
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
    }
}
