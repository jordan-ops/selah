import QtQuick
import Quickshell.Io
import "../services" as Services

// Command-backed frost slider — the renderer's `cmdslider` row type
// (output / input volume). The old knob dial's exact data plumbing in
// the unified slider language: reads ONCE at creation (readCommand's
// stdout scanned for the first /(\d+)%/ — pactl prints "Volume:
// front-left: 66846 / 102% / …"), every drag step coalesces through a
// 75 ms throttle (pactl applies instantly — a fast scrub must not
// fork-storm it) and the release flushes the final value. No
// Apply/Revert here: pactl has no baseline to revert to and volume
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

    width: 208                 // 140 slider + 10 + 58 readout, right-aligned
    height: 30
    readonly property real extraHeight: 0   // sliders never grow the row

    function clamp(v) { return Math.max(min, Math.min(max, v)) }

    function write(v) {
        const cmd = (e && e.writeCommand ? e.writeCommand : []).slice()
        cmd.push(v + root.suffix)
        if (cmd.length > 1) {
            wr.command = cmd
            wr.running = true
        }
    }

    // throttle: coalesce live scrubs ~75 ms apart; release flushes
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
                if (m) root.live = root.clamp(parseFloat(m[1]))
            }
        }
    }
    Process { id: wr }

    Row {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: 10

        SettingsFrostSlider {
            width: 140
            height: 30
            value: root.live
            from: root.min
            to: root.max
            step: root.step
            suffix: root.suffix
            // the M3 bubble needs ~32px of headroom above the handle the
            // 64px row doesn't spare — the always-on readout carries it
            showValueLabel: false
            onMoved: v => {
                root.live = root.clamp(v)
                root.requestWrite(Math.round(root.live))
            }
            onCommitted: v => {
                root.throttle.stop()
                root.queued = -1
                root.live = root.clamp(v)
                root.write(Math.round(root.live))
            }
        }

        // always-on % readout — accent like the info rows, right-aligned
        // in the same 208px zone the ctlZone reserves
        Text {
            anchors.verticalCenter: parent.verticalCenter
            font.family: Services.Fonts.family
            text: Math.round(root.live) + root.suffix
            font.pixelSize: 12
            font.bold: true
            color: Services.Colors.accent
            horizontalAlignment: Text.AlignRight
            width: 58
        }
    }
}
