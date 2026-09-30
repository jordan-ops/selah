pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    property real level: 1.0

    Process {
        id: brightnessProcess
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/(\d+)%/)
                if (match) root.level = parseInt(match[1]) / 100
            }
        }
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

    function increase(step) {
        brightnessProcess.command = ["brightnessctl", "set", step + "%+"]
        brightnessProcess.running = true
    }

    function decrease(step) {
        brightnessProcess.command = ["brightnessctl", "set", step + "%-"]
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
