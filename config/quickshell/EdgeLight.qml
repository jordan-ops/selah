import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import "./services" as Services

// Notification glow — adapted from Nebula's EdgeLight (GPL-3.0).
// A click-through top-strip overlay sweeps an accent-tinted light around
// the BAR PILL — geometry published live by Bar.qml through
// services/BarMetrics — when a notification lands, then destroys itself.
// Selah already shows the notification text in the pill itself, so this
// is the glow ONLY — no title/body pill of its own (Nebula's pill is
// dropped).
//
// Gates, in order: motion off = no decoration at all, GameMode = none,
// DoNotDisturb = none — except criticals, which exist precisely to break
// through DND. The effects.edgelight switch (Settings ▸ Animations or
// `qs ipc call settings set effects.edgelight false`) stops everything,
// including the test hook; the hook otherwise bypasses the motion gates:
//   qs ipc call edgelight test
Scope {
    id: root

    property color tint: Services.Colors.accent
    property string monitorName: ""
    property int serial: 0
    property bool running: false

    function wants(n) {
        if (!Services.Motion.motionOn)
            return false
        if (Services.GameMode.enabled)
            return false
        if (Services.DoNotDisturb.enabled && !n.isCritical)
            return false
        return true
    }

    function flash(color) {
        // the one switch that even the test hook respects — off means
        // nothing renders (motion/DND/game gates are bypassed by the hook)
        if (!Services.Settings.get("effects.edgelight", true))
            return
        root.tint = color
        root.monitorName = Hyprland.focusedMonitor?.name
            ?? (Quickshell.screens[0]?.name ?? "")
        root.serial++
        root.running = true
    }

    Connections {
        target: Services.Notifications
        function onNewNotification(n) {
            if (!root.wants(n))
                return
            root.flash(n.isCritical ? Services.Colors.critical
                                    : Services.Colors.accent)
        }
    }

    IpcHandler {
        target: "edgelight"
        function test(): void { root.flash(Services.Colors.accent) }
    }

    Loader {
        active: root.running
        visible: active

        sourceComponent: PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === root.monitorName)
                ?? Quickshell.screens[0]
            anchors { top: true; left: true; right: true }
            // Fixed strip = the bar window's max height (560) + glow
            // bleed — sized once, so the surface never resizes while the
            // pill morphs (the per-frame-resize lesson from Bar.qml), and
            // ~18× fewer pixels to composite than the full-screen overlay.
            implicitHeight: 620
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            // empty region = the glow never eats a click
            mask: Region {}
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "selah-edgelight"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // Nebula's timing kept (2.4s, 45% wash, two turns); band and
            // bleed retuned for the pill scale — a 70px screen-edge glow
            // swamps a 54px-tall pill.
            readonly property real thick: 4
            readonly property real glowPx: 44
            readonly property real glowA: 0.45
            readonly property int dur: 2400
            readonly property int turns: 2
            readonly property real tail: 23

            property real angle: 0
            property real sweep: 0
            property real wash: 0

            Connections {
                target: root
                function onSerialChanged() { anim.restart() }
            }

            SequentialAnimation {
                id: anim
                running: true
                onFinished: root.running = false
                ParallelAnimation {
                    // the light itself: two laps around the pill
                    NumberAnimation {
                        target: win; property: "angle"
                        from: 0; to: win.turns * Math.PI * 2
                        duration: win.dur
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: [0.4, 0, 0.2, 1, 1, 1]
                    }
                    // how much of the ring exists: head races out, holds,
                    // then the tail catches up and it is gone
                    SequentialAnimation {
                        NumberAnimation {
                            target: win; property: "sweep"
                            from: 0; to: 1; duration: win.dur * 0.12
                        }
                        PauseAnimation { duration: win.dur * 0.68 }
                        NumberAnimation {
                            target: win; property: "sweep"
                            to: 0; duration: win.dur * 0.2
                        }
                    }
                    // overall glow intensity: in over the first quarter,
                    // out over the rest
                    SequentialAnimation {
                        NumberAnimation {
                            target: win; property: "wash"
                            from: 0; to: win.glowA
                            duration: win.dur * 0.25
                            easing.type: Easing.OutQuad
                        }
                        NumberAnimation {
                            target: win; property: "wash"
                            to: 0; duration: win.dur * 0.75
                            easing.type: Easing.InOutQuad
                        }
                    }
                }
            }

            ShaderEffect {
                anchors.fill: parent
                property vector2d itemSize: Qt.vector2d(width, height)
                property color tint: root.tint
                property real angle: win.angle
                property real sweep: win.sweep
                property real wash: win.wash
                property real thick: win.thick
                property real glow: win.glowPx
                property real tailA: (100 - win.tail * 1.6) / 100
                property real tailB: (100 - win.tail * 0.6) / 100
                // live pill geometry — the glow orbits this rect; Bar
                // re-publishes on morphs so the orbit tracks a pill that
                // is still springing into notification mode
                readonly property var bm: Services.BarMetrics.rectFor(root.monitorName)
                property vector4d barRect: Qt.vector4d(bm.x, bm.y, bm.w, bm.h)
                property real radius: bm.r
                fragmentShader: Qt.resolvedUrl("shaders/edgelight.frag.qsb")
            }
        }
    }
}
