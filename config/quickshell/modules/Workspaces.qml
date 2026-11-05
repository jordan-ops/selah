import QtQuick
import Quickshell.Hyprland
import "../services"

// Compositor-aware workspace/tag strip.
//
// Hyprland: one dot per workspace that actually exists (not a fixed 1-9
// grid) — same behavior as Waybar's "hyprland/workspaces" with
// "all-outputs": false. The active workspace gets wider + accent-colored,
// the rest stay small and dim; special workspaces render as diamonds.
//
// mango: a fixed 1..tagNum grid fed by mmsg (Mango.tagsFor). Active tag
// = wider + accent; occupied tags sit brighter than empty ones so the
// strip reads like dwm's taglist; urgent flips to Colors.critical.
//
// Click switches — Hyprland workspace dispatch, mango `view,<tag>,0`.
Row {
    id: root
    spacing: 8

    readonly property bool mangoMode: Compositor.isMango

    // baseline of 1-5 always shown (like Waybar's persistent-workspaces), plus
    // any extra workspace ids that actually exist beyond 5 — deduped and sorted
    readonly property var workspaceIds: {
        let ids = new Set()
        for (let i = 1; i <= 5; i++) ids.add(i)
        for (const w of Hyprland.workspaces.values) ids.add(w.id)
        return Array.from(ids).sort((a, b) => a - b)
    }

    // mango: tags belong to a monitor — resolve which one by walking up to
    // the bar window's screen (each bar shows its own output's tags), with
    // the focused monitor as the fallback.
    readonly property string screenName: {
        let n = root
        while (n) {
            if (n.screen && n.screen.name) return n.screen.name
            n = n.parent
        }
        return Mango.focusedMonitor?.name ?? ""
    }
    readonly property var tagList: Mango.tagsFor(root.screenName)

    // unified delegate model: {id, active, occupied, urgent, special}
    readonly property var items: root.mangoMode
        ? root.tagList.map(t => ({
            id: t.index,
            active: t.is_active === true,
            occupied: t.client_count > 0,
            urgent: t.is_urgent === true,
            special: false
        }))
        : root.workspaceIds.map(id => ({
            id: id,
            active: Hyprland.focusedWorkspace?.id === id,
            occupied: false,
            urgent: false,
            special: id < 0   // Hyprland gives special/scratchpad workspaces a
                              // negative id — the documented way to tell them apart
        }))

    Repeater {
        model: root.items

        delegate: Rectangle {
            id: dot
            required property var modelData
            readonly property bool isActive: modelData.active
            readonly property bool isSpecial: modelData.special
            readonly property bool isUrgent: modelData.urgent
            // compact capsule is only 30px tall — keep the dots well inside
            // it (was 14/22, which read as huge next to the clock)
            width: isActive ? 16 : 10
            height: 10
            radius: isSpecial ? 2.5 : 5   // small radius = square-ish diamond, 5 = full circle
            rotation: isSpecial ? 45 : 0
            color: isUrgent && !isActive ? Colors.critical
                : isActive ? Colors.accent
                : Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b,
                          modelData.occupied ? 0.45 : 0.25)

            Behavior on width { SpringAnimation { spring: Motion.spatialFastSpring; damping: Motion.spatialFastDamping } }
            Behavior on color { ColorAnimation { duration: Motion.short3; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }

            MouseArea {
                anchors.fill: parent
                onClicked: Compositor.viewTag(dot.modelData.id)
            }
        }
    }
}
