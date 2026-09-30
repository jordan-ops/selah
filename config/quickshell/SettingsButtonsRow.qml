import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Horizontal button group — the `buttons` row type: every multi-choice
// setting drawn as one row of material-style chips (wraps when the set
// is wide, the row grows via extraHeight). Apply flavors, tried in
// order: option.command[] (shell out), entry.hyprKey (hyprctl eval),
// entry.settingsKey (settings.json). The same hyprKey / settingsKey /
// readCommand also live-reads the current value, so the chip that
// matches reality starts out highlighted (accel profile, focus mode,
// power profile, layout …). current starts as null: nothing is
// highlighted until a read lands, so a ""-valued option (accel
// "Default") never pre-selects itself.
Item {
    id: root

    property var e: null
    property var current: null

    readonly property real extraHeight: Math.max(0, flow.height - 64)

    width: 330
    height: flow.height

    function read() {
        if (!e) return
        if (e.hyprKey) {
            rd.command = ["hyprctl", "getoption", e.hyprKey]
            rd.running = true
        } else if (e.settingsKey) {
            current = Services.Settings.get(e.settingsKey, null)
        } else if (e.readCommand) {
            rd.command = e.readCommand
            rd.running = true
        }
    }

    function apply(opt) {
        if (!e) return
        if (opt.command) {
            act.command = opt.command
            act.running = true
            return
        }
        if (e.hyprKey) {
            // Apply/Revert baseline: what getoption last reported (a
            // null current means no read landed — nothing to revert to)
            if (root.current !== null && root.current !== undefined)
                Services.SettingsApp.hyprChanged(e.hyprKey, root.current, opt.value)
            current = opt.value   // optimistic; the re-read settles it
            wr.command = ["hyprctl", "eval",
                Services.SettingsCatalog.hyprEval(e.hyprKey,
                    Services.SettingsCatalog.hyprLuaValue(opt.value))]
            wr.running = true
            rdDelay.restart()
        } else if (e.settingsKey) {
            Services.Settings.set(e.settingsKey, opt.value)
            current = opt.value
        }
    }

    Component.onCompleted: read()

    // Revert evaled baselines back — re-read so the highlighted chip
    // matches what hyprland now holds
    Connections {
        target: Services.SettingsApp
        function onRevertDone() { if (!rd.running) root.read() }
    }

    Process { id: wr }
    Process {
        id: act
        onExited: root.read()
    }
    Process {
        id: rd
        stdout: StdioCollector {
            onStreamFinished: {
                if (root.e && root.e.hyprKey) {
                    const v = Services.SettingsCatalog.hyprParse(text)
                    root.current = v === null || v === undefined ? null : v
                } else {
                    const t = text.trim()
                    root.current = t === "" ? null : t
                }
            }
        }
    }
    Timer { id: rdDelay; interval: 150; onTriggered: root.read() }

    Flow {
        id: flow
        anchors.right: parent.right
        width: root.width
        spacing: 6

        Repeater {
            model: root.e ? (root.e.options || []) : []

            delegate: Rectangle {
                readonly property bool selected:
                    root.current !== null
                    && String(modelData.value) === String(root.current)
                height: 28
                radius: 14
                width: btnLabel.width + 26
                color: selected ? Services.Colors.accent
                    : (chipMouse.containsMouse ? Services.Colors.surfaceAlt
                                               : Services.Colors.surface)

                Behavior on color {
                    ColorAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }

                Text {
                    font.family: Services.Fonts.family
                    id: btnLabel
                    anchors.centerIn: parent
                    text: modelData.label
                    font.pixelSize: 12
                    font.bold: selected
                    color: parent.selected ? Services.Colors.background : Services.Colors.textMuted

                    Behavior on color {
                        ColorAnimation {
                            duration: Services.Motion.effectsFast
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }
                    }
                }

                MouseArea {
                    id: chipMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.apply(modelData)
                }
            }
        }
    }
}
