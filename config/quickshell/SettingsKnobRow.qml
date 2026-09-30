import QtQuick
import Quickshell.Io
import "./services" as Services

// Knob row for command-backed percent values — the renderer's `knob`
// row type (output / input volume). Reads ONCE at creation:
// readCommand's stdout scanned for the first /(\d+)%/ (pactl prints
// "Volume: front-left: 66846 / 102% / …"). Writes: every turned step
// coalesces through a 75 ms throttle (pactl applies instantly — a fast
// spin must not fork-storm it) and the final value flushes on release.
// No Apply/Revert here: pactl has no baseline to revert to and volume
// lives in pipewire — same class as cmdswitch rows (immediate), not
// hyprKey rows (pending + user-settings.lua).
Item {
    id: root

    property var e: null
    readonly property real min: e && e.min !== undefined ? Number(e.min) : 0
    readonly property real max: e && e.max !== undefined ? Number(e.max) : 150
    readonly property real step: e && e.step !== undefined ? Number(e.step) : 1
    readonly property string suffix: e && e.suffix !== undefined ? String(e.suffix) : "%"

    property real live: min    // what the sink/source holds

    width: 96                  // 52 knob, right-aligned in the zone
    height: 30
    readonly property real extraHeight: 0   // knobs never grow the row

    function clamp(v) { return Math.max(min, Math.min(max, v)) }

    function write(v) {
        const cmd = (e && e.writeCommand ? e.writeCommand : []).slice()
        cmd.push(v + root.suffix)
        if (cmd.length > 1) {
            wr.command = cmd
            wr.running = true
        }
    }

    // throttle: coalesce live turns ~75 ms apart; release flushes
    property real queued: -1
    function requestWrite(v) {
        queued = v
        if (!throttle.running) {
            write(v)
            throttle.start()
        }
    }
    Timer {
        id: throttle
        interval: 75
        onTriggered: {
            if (root.queued >= 0) root.write(root.queued)
            root.queued = -1
        }
    }

    Component.onCompleted: rd.running = true

    Process {
        id: rd
        command: e && e.readCommand ? e.readCommand : ["true"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /(\d+(?:\.\d+)?)%/.exec(text)
                if (m) {
                    root.live = root.clamp(parseFloat(m[1]))
                    if (!knob.dragging) knob.value = root.live
                }
            }
        }
    }
    Process { id: wr }

    SettingsKnob {
        id: knob
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        value: root.live
        min: root.min
        max: root.max
        step: root.step
        suffix: root.suffix
        onMoved: v => root.requestWrite(v)
        onCommitted: v => {
            throttle.stop()
            root.queued = -1
            root.live = root.clamp(v)
            root.write(v)
        }
    }
}
