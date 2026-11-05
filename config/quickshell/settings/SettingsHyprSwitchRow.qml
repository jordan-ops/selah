import QtQuick
import Quickshell.Io
import "../services" as Services

// The window's switch, but backed by a live Hyprland option instead of a
// stored pref — the `hyprswitch` row type. State is read from
// hyprctl getoption on load and written with hyprctl eval on flip, so the
// pill always shows what the compositor actually holds. Entries with a
// `persistKey` also record their value in settings.json; SettingsApp
// re-applies those once at shell start (hyprctl eval is runtime-only, and
// the hypr Lua files are the displays-persistence exception, not ours).
// On/Off text sits beside the pill so the state reads at a glance.
Item {
    id: root

    property var e: null
    property bool on: false
    readonly property real extraHeight: 0

    width: 76
    height: 24

    Accessible.role: Accessible.Button
    Accessible.name: (root.e && root.e.label ? root.e.label : "Toggle")
        + " — " + (root.on ? "on" : "off")

    Component.onCompleted: readProc.running = true

    // Revert evaled baselines back inside hyprland — re-read so the pill
    // shows the restored state, not the reverted-away one
    Connections {
        target: Services.SettingsApp
        function onRevertDone() { if (!readProc.running) readProc.running = true }
    }

    function flip() { root.setTo(!root.on) }
    function setTo(target) {
        const next = !!target
        if (root.on === next) return
        // Apply/Revert baseline must capture the OLD state first
        Services.SettingsApp.hyprChanged(e.hyprKey, root.on, next)
        root.on = next
        writeProc.command = ["hyprctl", "eval",
            Services.SettingsCatalog.hyprEval(e.hyprKey,
                                               Services.SettingsCatalog.hyprLuaValue(next))]
        writeProc.running = true
        if (e && e.persistKey)
            Services.Settings.set(e.persistKey, next)
    }
    // per-row reset affordance in the window's row delegate
    function resetToDefault() {
        if (!root.e || root.e.default === undefined) return
        root.setTo(root.e.default === true || root.e.default === "true")
    }

    Process {
        id: readProc
        command: ["hyprctl", "getoption", root.e ? root.e.hyprKey : ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = Services.SettingsCatalog.hyprParse(text)
                if (typeof v === "boolean") root.on = v
            }
        }
    }
    Process {
        id: writeProc
        // hyprctl eval exits nonzero (7 on this build) for a bad chunk —
        // tell the user instead of silently keeping the old state
        onExited: (exitCode) => {
            if (exitCode !== 0)
                SettingsToast.push("«" + (root.e && root.e.label ? root.e.label
                                           : "Setting")
                                   + "» — hyprctl eval failed", true)
        }
    }

    Row {
        anchors.fill: parent
        spacing: 8

        Text {
            font.family: Services.Fonts.family
            width: 24
            height: 24
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignRight
            text: root.on ? "On" : "Off"
            font.pixelSize: 12
            font.bold: true
            color: root.on ? Services.Colors.accent : Services.Colors.textMuted

            Behavior on color {
                ColorAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }
        }

        Rectangle {
            width: 44
            height: 24
            radius: 12
            color: root.on ? Services.Colors.accent : Services.Colors.surface

            Behavior on color {
                ColorAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }

            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                x: root.on ? parent.width - width - 3 : 3
                width: 18
                height: 18
                radius: 9
                color: root.on ? Services.Colors.background : Services.Colors.textMuted

                Behavior on color {
                    ColorAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }

                // knob throw — the pop spring overshoots the end stop and
                // snaps back: the M3 switch bounce, felt not just seen
                Behavior on x {
                    SpringAnimation {
                        spring: Services.Motion.popSpring
                        damping: Services.Motion.popDamping
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.flip()
            }
        }
    }
}
