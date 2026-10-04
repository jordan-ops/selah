pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick

// Desktop click ripples — the state half of the effect, ported from
// Nebula's DesktopRipple (GPL-3.0): a small pool of timed slots
// (x, y, born-at, amplitude) that Background.qml's ShaderEffect samples
// as uniforms. Ripples live only while one is on screen, so the
// FrameAnimation clock and the shader both cost nothing at rest.
//
// Gates instead of a setting, per this shell's motion philosophy:
// Motion.motionOn off = no decoration at all, GameMode = no decoration.
// Drag spawns are throttled here (110 ms, amp 0.6) so a fast sweep
// paints a dotted trail rather than a solid smear.
Singleton {
    id: root

    readonly property int lifeMs: 2600
    readonly property int slots: 10
    readonly property real strength: 1.0

    property var ripples: []
    property string monitorName: ""
    property bool alive: false
    property double now: 0
    property double lastDrag: 0

    readonly property bool moving: alive && ripples.some(r => now - r.t0 < lifeMs)

    function spawn(screenName, x, y, amp) {
        if (!Motion.motionOn || GameMode.enabled)
            return
        const t = Date.now()
        // switching screens starts a fresh pool — old slots would be in
        // the wrong coordinate space anyway
        const same = screenName === root.monitorName
        const list = same ? root.ripples.filter(r => t - r.t0 < root.lifeMs) : []
        list.push({ x: x, y: y, t0: t, amp: amp ?? 1 })
        while (list.length > root.slots)
            list.shift()
        root.monitorName = screenName
        root.now = t
        root.ripples = list
        root.alive = true
        idle.restart()
    }

    // pointer-drag trail — throttled so one sweep = a few ripples
    function spawnDrag(screenName, x, y) {
        const t = Date.now()
        if (t - root.lastDrag < 110)
            return
        root.lastDrag = t
        spawn(screenName, x, y, 0.6)
    }

    // one slot as the shader wants it: (x, y, age-seconds, amplitude);
    // t < 0 marks an empty slot (the shader treats it as inactive)
    function uniformFor(i) {
        const r = root.ripples[i]
        if (!r)
            return Qt.vector4d(0, 0, -1, 0)
        return Qt.vector4d(r.x, r.y, (root.now - r.t0) / 1000, r.amp)
    }

    // motion turned off mid-animation: drop everything rather than leave
    // a frozen ring on the desktop
    Connections {
        target: Motion
        function onMotionOnChanged() {
            if (!Motion.motionOn) {
                root.ripples = []
                root.alive = false
            }
        }
    }

    Timer {
        id: idle
        interval: 8000
        onTriggered: root.alive = false
    }

    FrameAnimation {
        running: root.moving
        onTriggered: root.now = Date.now()
    }

    IpcHandler {
        target: "ripple"
        // qs ipc call ripple at 500 400 — test hook
        function at(x: real, y: real): void {
            root.spawn(Quickshell.screens[0]?.name ?? "", x, y, 1)
        }
    }
}
