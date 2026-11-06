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
        : root.workspaceIds.map(id => {
            const ws = Hyprland.workspaces.values.find(w => w.id === id)
            return {
                id: id,
                active: Hyprland.focusedWorkspace?.id === id,
                occupied: ws && ws.windows ? ws.windows.length > 0 : false,
                urgent: false,
                special: id < 0   // Hyprland gives special/scratchpad workspaces a
                                  // negative id — the documented way to tell them apart
            }
        })

    Repeater {
        model: root.items
        // spacing: 2  // QML engine – natural gap via delegate width
        // delegate width 16 gives ~5px gap between 6px dots center-to-center
        // spacing: 2  // removed – QML engine does not expose this property
        // natural gap achieved via delegate width + content

        delegate: Item {
            id: wrap
            width: 14
            height: 18
            required property var modelData
            readonly property bool isActive: modelData.active
            readonly property bool isUrgent: modelData.urgent

            // glow behind the active workspace — larger translucent
            // accent rect, sits behind the box so it bleeds slightly
            Rectangle {
                width: 10
                height: 14
                radius: 4
                color: isActive
                    ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.30)
                    : "transparent"
                anchors.centerIn: parent
                Behavior on color { ColorAnimation { duration: Motion.short3; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }
            }

            // the box itself: slight rounded corners, always the same
            // size so the strip never churns as workspaces activate
            Rectangle {
                id: dot
                width: 6
                height: 12
                radius: 3
                color: isUrgent && !isActive ? Colors.critical
                    : isActive ? Colors.accent
                    : modelData.occupied ? Qt.rgba(Colors.accent.r, Colors.accent.g, Colors.accent.b, 0.22)
                    : Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.14)
                anchors.centerIn: parent
                Behavior on color { ColorAnimation { duration: Motion.short3; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Compositor.viewTag(wrap.modelData.id)
                }
            }
        }
    }
}
