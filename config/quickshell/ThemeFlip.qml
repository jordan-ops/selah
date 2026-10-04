import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./services" as Services

// Theme-switch reveal — adapted from Nebula's ThemeFlip (GPL-3.0),
// re-hinged onto Themes.applyStarted/applyFinished instead of its
// wallpaper service's flipPhase: while switch-theme.sh runs, every screen
// shows a frozen frame of itself (ScreencopyView under a click-through
// overlay), and once the new theme has landed and settled, the frozen
// frame irises out toward the cursor over the motion system's long reveal
// — the desktop appears to flip in place.
//
// Fire-and-forget: the overlay never delays or blocks the apply, and
// every exit path tears it down — failed apply, capture that never
// arrives (600 ms fallback), and a 25 s stuck-state watchdog. Test hook
// captures and reveals without applying anything:
//   qs ipc call themeflip test
Scope {
    id: root

    // idle → capturing → frozen (frame up; apply may still be running)
    // → revealing → idle
    property string phase: "idle"
    property int held: 0
    property bool testMode: false
    property point flipPoint: Qt.point(-1, -1)

    readonly property bool active: phase !== "idle"

    function begin(isTest) {
        if (active || !Services.Motion.motionOn)
            return
        if (!isTest && Services.GameMode.enabled)
            return
        held = 0
        testMode = isTest
        // cursor position for the iris centre — captured now, while the
        // pointer still sits on whatever picker entry started the switch
        cursorProc.running = true
        phase = "capturing"
        captureFallback.restart()
    }

    // every screen has frozen its frame (or the fallback gave up): hold
    // it visible until the apply reports finished, then settle briefly
    // so colors.json's hot-reload has rendered under the frozen frame
    function frozen() {
        captureFallback.stop()
        phase = "frozen"
        if (root.testMode)
            settle.restart()
    }

    function frameHeld() {
        held++
        if (held >= Quickshell.screens.length && phase === "capturing")
            frozen()
    }

    function finish() {
        settle.stop()
        phase = "idle"
        testMode = false
    }

    Connections {
        target: Services.Themes
        function onApplyStarted() { root.begin(false) }
        function onApplyFinished() {
            // capture may still be in flight when the script exits —
            // stop waiting and move on
            if (root.phase === "capturing")
                root.frozen()
            if (root.phase === "frozen")
                settle.restart()
        }
    }

    Timer {
        id: captureFallback
        interval: 600
        onTriggered: if (root.phase === "capturing") root.frozen()
    }

    // colors land before switch-theme.sh exits, but the wallpaper Image
    // may still be decoding under the frozen frame — one short beat
    Timer {
        id: settle
        interval: 350
        onTriggered: root.phase = "revealing"
    }

    Timer {
        running: root.phase === "revealing"
        interval: Services.Motion.extraLong1 + 400
        onTriggered: root.finish()
    }

    // watchdog: a lost applyFinished must never leave a frozen screen
    Timer {
        running: root.active
        interval: 25000
        onTriggered: root.finish()
    }

    Process {
        id: cursorProc
        command: ["hyprctl", "cursorpos"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(",")
                const x = parseInt(p[0]), y = parseInt(p[1])
                if (!isNaN(x) && !isNaN(y))
                    root.flipPoint = Qt.point(x, y)
            }
        }
    }

    IpcHandler {
        target: "themeflip"
        function test(): void { root.begin(true) }
    }

    // fresh windows (and therefore a fresh one-shot ScreencopyView) on
    // every arm — that is what re-captures for the next flip
    Variants {
        model: root.active ? Quickshell.screens : []

        PanelWindow {
            id: win
            required property var modelData
            screen: modelData

            anchors { top: true; left: true; right: true; bottom: true }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "selah-themeflip"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            readonly property point center: {
                const p = root.flipPoint
                return p.x >= 0 ? Qt.point(p.x - win.modelData.x, p.y - win.modelData.y)
                                : Qt.point(win.width / 2, win.height / 2)
            }
            // radius must clear the farthest corner for the frame to be
            // fully gone at the end of the reveal
            readonly property real far: Math.max(
                Math.hypot(win.center.x, win.center.y),
                Math.hypot(win.width - win.center.x, win.center.y),
                Math.hypot(win.center.x, win.height - win.center.y),
                Math.hypot(win.width - win.center.x, win.height - win.center.y))
            // -2 → the shader's keep-mask covers the whole surface (the
            // frozen frame in full); growing past `far` empties it
            property real radius: -2

            ScreencopyView {
                anchors.fill: parent
                captureSource: win.modelData
                live: false
                paintCursor: false
                onHasContentChanged: if (hasContent) heldTimer.start()
                layer.enabled: true
                layer.effect: ShaderEffect {
                    property vector2d itemSize: Qt.vector2d(width, height)
                    property vector2d center: Qt.vector2d(win.center.x, win.center.y)
                    property real radius: win.radius
                    fragmentShader: Qt.resolvedUrl("shaders/themeflip.frag.qsb")
                }
            }

            Timer {
                id: heldTimer
                interval: 34
                onTriggered: root.frameHeld()
            }

            // iris out toward the cursor: the frozen frame shrinks into
            // the point, revealing the new theme around it
            NumberAnimation {
                target: win
                property: "radius"
                from: -2
                to: win.far + 4
                duration: Services.Motion.extraLong1
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.emphasizedCurve
                running: root.phase === "revealing"
            }
        }
    }
}
