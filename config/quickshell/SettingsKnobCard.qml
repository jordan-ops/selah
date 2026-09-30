import QtQuick
import Quickshell.Io
import "./services" as Services

// Window opacity card — the `knobcard` row type: ONE material card with
// a rotary knob per option (decoration:active/inactive/fullscreen_
// opacity → Active / Inactive / Fullscreen). Layout follows
// SettingsPowerCard (label-block spacer + tonal card); every cell
// commits EXACTLY like SettingsSliderRow — baseline into
// SettingsApp.hyprChanged so Apply/Revert sees it, then a live hyprctl
// eval — and reads its own option once with hyprctl getoption (scale
// maps 0.5–1.0 → the 50–100 the dial shows). Release-only writes: the
// dial previews, release commits (the slider's mid-drag-write rule).
Item {
    id: root

    property var e: null
    readonly property real extraHeight: Math.max(0, col.implicitHeight - 64)
    height: col.implicitHeight

    Column {
        id: col
        width: parent.width
        spacing: 10

        Item { width: 1; height: 50 }   // clears the row's label block

        Rectangle {
            id: card
            width: col.width
            height: kbRow.implicitHeight + 28
            radius: 16
            color: Services.Colors.surface
            border.color: Services.Colors.low
            border.width: 1

            Row {
                id: kbRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 0

                Repeater {
                    model: root.e && root.e.knobs ? root.e.knobs : []

                    delegate: Column {
                        id: kd
                        readonly property var md: modelData
                        readonly property real sc: md.scale !== undefined ? Number(md.scale) : 1
                        readonly property real kmin: md.min !== undefined ? Number(md.min) : 0
                        readonly property real kmax: md.max !== undefined ? Number(md.max) : 100
                        readonly property real kstep: md.step !== undefined ? Number(md.step) : 1
                        property real live: kmin
                        width: kbRow.width / Math.max(1, root.e.knobs.length)
                        spacing: 7

                        // SettingsSliderRow.commit, verbatim — baseline for
                        // Apply/Revert, then the live eval
                        function commit(next) {
                            const stored = Number((next * sc).toFixed(3))
                            Services.SettingsApp.hyprChanged(md.hyprKey,
                                Number((live * sc).toFixed(3)), stored)
                            wr.command = ["hyprctl", "eval",
                                Services.SettingsCatalog.hyprEval(md.hyprKey,
                                    Services.SettingsCatalog.hyprLuaValue(stored))]
                            wr.running = true
                            live = next
                        }

                        Component.onCompleted: rd.running = true

                        // Revert evaled baselines back — re-read so the
                        // dial lands on the restored value
                        Connections {
                            target: Services.SettingsApp
                            function onRevertDone() {
                                if (!rd.running) rd.running = true
                            }
                        }

                        Process {
                            id: rd
                            command: ["hyprctl", "getoption", kd.md.hyprKey || ""]
                            stdout: StdioCollector {
                                onStreamFinished: {
                                    const v = Services.SettingsCatalog.hyprParse(text)
                                    if (typeof v === "number" && !knob.dragging) {
                                        kd.live = Math.max(kd.kmin, Math.min(kd.kmax, v / kd.sc))
                                        knob.value = kd.live
                                    }
                                }
                            }
                        }
                        Process { id: wr }

                        Item {
                            width: parent.width
                            height: knob.implicitHeight

                            SettingsKnob {
                                id: knob
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.verticalCenter: parent.verticalCenter
                                value: kd.kmin
                                min: kd.kmin
                                max: kd.kmax
                                step: kd.kstep
                                suffix: md.suffix !== undefined ? String(md.suffix) : "%"
                                onCommitted: v => kd.commit(v)
                            }
                        }

                        Text {
                            font.family: Services.Fonts.family
                            width: parent.width
                            horizontalAlignment: Text.AlignHCenter
                            text: kd.md.label || ""
                            font.pixelSize: 11
                            color: Services.Colors.textMuted
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }
}
