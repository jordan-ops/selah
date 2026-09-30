import QtQuick
import Quickshell.Hyprland
import "../services"

// One dot per workspace that actually exists (not a fixed 1-9 grid) — same
// behavior as Waybar's "hyprland/workspaces" with "all-outputs": false.
// The active workspace gets wider + accent-colored, the rest stay small and dim.
Row {
    id: root
    spacing: 8

    // baseline of 1-5 always shown (like Waybar's persistent-workspaces), plus
    // any extra workspace ids that actually exist beyond 5 — deduped and sorted
    readonly property var workspaceIds: {
        let ids = new Set()
        for (let i = 1; i <= 5; i++) ids.add(i)
        for (const w of Hyprland.workspaces.values) ids.add(w.id)
        return Array.from(ids).sort((a, b) => a - b)
    }

    Repeater {
        model: root.workspaceIds

        delegate: Rectangle {
            id: dot
            required property int modelData
            property bool isActive: Hyprland.focusedWorkspace?.id === modelData
            // Hyprland gives special/scratchpad workspaces a negative id — that's
            // the documented, reliable way to tell them apart from regular ones
            property bool isSpecial: modelData < 0
            // compact capsule is only 30px tall — keep the dots well inside
            // it (was 14/22, which read as huge next to the clock)
            width: isActive ? 16 : 10
            height: 10
            radius: isSpecial ? 2.5 : 5   // small radius = square-ish diamond, 5 = full circle
            rotation: isSpecial ? 45 : 0
            color: isActive ? Colors.accent : Qt.rgba(Colors.text.r, Colors.text.g, Colors.text.b, 0.25)

            Behavior on width { SpringAnimation { spring: Motion.spatialFastSpring; damping: Motion.spatialFastDamping } }
            Behavior on color { ColorAnimation { duration: Motion.short3; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardCurve } }

            MouseArea {
                anchors.fill: parent
                onClicked: Hyprland.dispatch("workspace " + dot.modelData)
            }
        }
    }
}
