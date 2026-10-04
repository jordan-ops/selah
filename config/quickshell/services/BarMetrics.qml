pragma Singleton
import QtQuick
import Quickshell

// Live geometry of each screen's bar pill, published by Bar.qml —
// EdgeLight orbits this rect so the notification glow hugs the bar
// itself instead of the screen edge. `rects` is reassigned on every
// pill geometry change (morphs, tray slot, content width), so readers
// binding through rectFor() repaint live while the glow animates.
Singleton {
    id: root

    // screen name -> { x, y, w, h, r } in global (hyprland) coordinates
    property var rects: ({})

    function update(name, g) {
        if (!name)
            return
        const next = {}
        Object.assign(next, root.rects)
        next[name] = g
        root.rects = next
    }

    // sensible stand-in before the bar has published (or if it is
    // hidden): centered 300×54 pill along the top, full-pill corners
    function rectFor(name) {
        return root.rects[name] || { x: 810, y: 0, w: 300, h: 54, r: 27 }
    }
}
