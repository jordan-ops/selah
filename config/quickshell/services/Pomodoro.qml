pragma Singleton
import Quickshell
import QtQuick

// Waybar analogy: this is like a "custom/pomodoro" module that keeps a
// countdown running via a script's internal state, except the state lives
// here permanently instead of getting re-read from a file every interval.
// Runs whether or not the clock popup is open — same reasoning as
// Services.ControlCenter existing outside the panel it drives.
Singleton {
    id: root

    property bool running: false
    property string phase: "work"        // "work" | "break" | "longBreak"

    property int workMinutes: 25
    property int breakMinutes: 5
    property int longBreakMinutes: 15
    property int cyclesBeforeLongBreak: 4

    property int completedCycles: 0
    property int remainingSeconds: workMinutes * 60

    readonly property string display: {
        const m = Math.floor(root.remainingSeconds / 60)
        const s = root.remainingSeconds % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    readonly property string phaseLabel: phase === "work" ? "Focus"
        : phase === "break" ? "Short Break" : "Long Break"

    // length of the CURRENT phase + its remaining fraction — the clock
    // card's ring draws from these (Behavior smooths the 1s ticks into a
    // continuous sweep)
    readonly property int phaseTotalSeconds: phase === "work" ? workMinutes * 60
        : phase === "break" ? breakMinutes * 60 : longBreakMinutes * 60
    readonly property real progress:
        phaseTotalSeconds > 0 ? remainingSeconds / phaseTotalSeconds : 0

    function start() { root.running = true }
    function pause() { root.running = false }

    function reset() {
        root.running = false
        root.phase = "work"
        root.completedCycles = 0
        root.remainingSeconds = root.workMinutes * 60
    }

    function skip() { advancePhase() }

    function advancePhase() {
        if (root.phase === "work") {
            root.completedCycles++
            root.phase = (root.completedCycles % root.cyclesBeforeLongBreak === 0) ? "longBreak" : "break"
        } else {
            root.phase = "work"
        }
        root.remainingSeconds = root.phase === "work" ? root.workMinutes * 60
            : root.phase === "break" ? root.breakMinutes * 60
            : root.longBreakMinutes * 60
    }

    Timer {
        interval: 1000
        running: root.running
        repeat: true
        onTriggered: {
            if (root.remainingSeconds > 0) root.remainingSeconds--
            else root.advancePhase()
        }
    }
}
