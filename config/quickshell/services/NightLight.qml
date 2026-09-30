pragma Singleton
import Quickshell
import Quickshell.Io

// Waybar analogy: think of hyprsunset like `mpd` — it's a long-running
// background process, not a one-shot command. "Toggling" it really means
// "start the process" / "kill the process", same as a Waybar module that
// starts/stops a daemon rather than just flipping a config value.
Singleton {
    id: root

    property bool active: false
    property int temperature: 4000   // lower = warmer. hyprsunset default "day" is 6000

    function toggle() {
        if (root.active) {
            stopProc.running = true
        } else {
            startProc.command = ["hyprsunset", "-t", String(root.temperature)]
            startProc.running = true
            root.active = true
        }
    }

    // the long-lived process itself
    Process {
        id: startProc
        onExited: root.active = false   // if it crashes/gets killed elsewhere, stay in sync
    }

    Process {
        id: stopProc
        command: ["pkill", "hyprsunset"]
        onExited: root.active = false
    }

    // on Quickshell startup, check if hyprsunset was already running
    // (e.g. you restarted the shell but not hyprsunset itself)
    Process {
        id: checkProc
        command: ["pgrep", "-x", "hyprsunset"]
        running: true
        onExited: exitCode => root.active = (exitCode === 0)
    }

    // same IPC pattern as ControlCenter/PowerMenu — Hyprland keybind entry point
    IpcHandler {
        target: "nightlight"
        function toggle(): void { root.toggle() }
    }
}
