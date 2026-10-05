pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property real level: 1.0
    // set by the first stdout that carries a percentage — level starts at
    // 1.0 only until then. The bar's OSD Connections read this so the
    // start-up query doesn't announce itself as if a key were pressed
    property bool seeded: false

    Process {
        id: brightnessProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/(\d+)%/)
                if (match) {
                    root.level = parseInt(match[1]) / 100
                    root.seeded = true
                }
            }
        }
    }

    // seed level from the real backlight at startup — brightnessctl with
    // no args prints "Current brightness: … (50%)", which the parser above
    // picks up. Without this the control-center slider opens at 100 % no
    // matter what the panel is actually doing
    Component.onCompleted: read()

    function read() {
        brightnessProcess.command = ["brightnessctl"]
        brightnessProcess.running = true
    }

    function setBrightness(percent) {
        brightnessProcess.command = ["brightnessctl", "set", percent + "%"]
        brightnessProcess.running = true
    }

    // control-center slider entry point — slider works in 0..1 like the
    // volume slider, brightnessctl wants a percent
    function setLevel(v) {
        setBrightness(Math.round(v * 100))
    }

    // -e4 -n2 kept from the original Hyprland bind (exponent steps, floor
    // of 2) — the feel of the brightness keys is the user's, not mine.
    // The bind now calls these over IPC instead of shelling brightnessctl
    // itself, which is what makes `level` (and therefore the pill OSD) move
    function increase(step) {
        brightnessProcess.command = ["brightnessctl", "-e4", "-n2", "set", step + "%+"]
        brightnessProcess.running = true
    }

    function decrease(step) {
        brightnessProcess.command = ["brightnessctl", "-e4", "-n2", "set", step + "%-"]
        brightnessProcess.running = true
    }

    IpcHandler {
        target: "brightness"

        function set(percent: real): void {
            root.setBrightness(percent)
        }
        function increase(step: real): void {
            root.increase(step)
        }
        function decrease(step: real): void {
            root.decrease(step)
        }
    }
}
