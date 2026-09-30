import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Motion controls — the `animcard` row type (Animations page): three
// independent groups so each motion domain can be tuned alone, plus a
// global group that drives both targets at once:
//   Global     → motion.enabled + animations:enabled together
//   Quickshell → Motion.qml only (settings.json → live bindings)
//   Hyprland   → animations:enabled (eval now, Apply persists it into
//                user-settings.lua, persistKey re-applies it at session
//                start) / hypr.speedScale (SettingsApp re-evals the
//                scaled appearance.lua set on every change)
// The compositor half of every pill mirrors SettingsHyprSwitchRow's
// hyprChanged + eval + persistKey flow (baseline first, so Revert and
// Apply see the old value); the shell half is settings.json like every
// `switch` row. Speed chips are settings.json too — immediate, no Apply
// (same rule as cmdswitch/knob rows).
Item {
    id: root

    // the renderer passes the catalog entry to every row component
    property var e: null

    readonly property real extraHeight: Math.max(0, col.implicitHeight - 64)
    width: parent ? parent.width : 760
    height: col.implicitHeight

    readonly property bool shellOn: {
        const v = Services.Settings.values["motion.enabled"]
        return !(v === false || v === "false")
    }
    readonly property real shellSpeed:
        root.num(Services.Settings.values["motion.speedScale"], 1)
    readonly property real hyprSpeed:
        root.num(Services.Settings.values["hypr.speedScale"], 1)
    property bool hyprOn: false

    // the harness-proven band (tst_anim / tst_anim2: overshoot stays in
    // the tuned bands at 0.5–1.5; 2× inflates them ~2×, so it's out)
    readonly property var speeds: [
        { v: 0.5,  label: "0.5×" },
        { v: 0.75, label: "0.75×" },
        { v: 1,    label: "1×" },
        { v: 1.25, label: "1.25×" },
        { v: 1.5,  label: "1.5×" }
    ]

    function num(v, dflt) {
        const n = Number(v)
        return isNaN(n) ? dflt : n
    }
    function near(a, b) { return Math.abs(a - b) < 0.01 }

    function readHypr() {
        if (!readProc.running) readProc.running = true
    }
    Component.onCompleted: readHypr()

    // Revert evaled baselines back inside hyprland — re-read so the pills
    // show the restored state, not the reverted-away one
    Connections {
        target: Services.SettingsApp
        function onRevertDone() { root.readHypr() }
    }

    function flipShell(next) {
        Services.Settings.set("motion.enabled", next)
    }

    function flipHypr(next) {
        // Apply/Revert baseline must capture the OLD state first
        Services.SettingsApp.hyprChanged("animations:enabled", root.hyprOn, next)
        root.hyprOn = next
        writeProc.command = ["hyprctl", "eval",
            Services.SettingsCatalog.hyprEval("animations:enabled",
                Services.SettingsCatalog.hyprLuaValue(next))]
        writeProc.running = true
        Services.Settings.set("hypr.animationsEnabled", next)
    }

    function pillOn(group) {
        if (group === "global") return root.shellOn && root.hyprOn
        if (group === "shell") return root.shellOn
        return root.hyprOn
    }

    function pillTap(group) {
        if (group === "shell") { root.flipShell(!root.shellOn); return }
        if (group === "hypr")  { root.flipHypr(!root.hyprOn); return }
        // global: both on → everything off; anything else (one off, both
        // off) → everything on, so a mixed state always resolves forward
        const next = !(root.shellOn && root.hyprOn)
        root.flipShell(next)
        root.flipHypr(next)
    }

    function chipOn(group, v) {
        if (group === "global")
            return root.near(root.shellSpeed, v) && root.near(root.hyprSpeed, v)
        if (group === "shell") return root.near(root.shellSpeed, v)
        return root.near(root.hyprSpeed, v)
    }

    function setSpeed(group, v) {
        if (group !== "hypr")  Services.Settings.set("motion.speedScale", v)
        if (group !== "shell") Services.Settings.set("hypr.speedScale", v)
    }

    Process {
        id: readProc
        command: ["hyprctl", "getoption", "animations:enabled"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = Services.SettingsCatalog.hyprParse(text)
                if (typeof v === "boolean") root.hyprOn = v
            }
        }
    }
    Process { id: writeProc }

    Column {
        id: col
        width: parent.width
        spacing: 10

        Item { width: 1; height: 50 }   // clears the row's label block

        Rectangle {
            // elevated card — SettingsPowerCard's visual language
            width: col.width
            height: inner.implicitHeight + 24
            radius: 16
            color: Services.Colors.surface
            border.color: Services.Colors.low
            border.width: 1

            Column {
                id: inner
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: 6

                Repeater {
                    model: [
                        { name: "Global",     hint: "quickshell + Hyprland",
                          group: "global" },
                        { name: "Quickshell", hint: "bar, popups, cards",
                          group: "shell" },
                        { name: "Hyprland",   hint: "windows, workspaces",
                          group: "hypr" }
                    ]

                    delegate: Item {
                        id: grp
                        property var g: modelData
                        width: inner.width
                        height: 34

                        Row {
                            anchors.left: parent.left
                            anchors.right: rightSide.left
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 6

                            Text {
                                font.family: Services.Fonts.family
                                id: grpName
                                text: grp.g.name
                                font.pixelSize: 13
                                font.bold: true
                                color: Services.Colors.text
                            }
                            Text {
                                font.family: Services.Fonts.family
                                text: grp.g.hint
                                width: Math.max(0, parent.width
                                                - grpName.implicitWidth - 6)
                                font.pixelSize: 11
                                color: Services.Colors.textMuted
                                elide: Text.ElideRight
                                verticalAlignment: Text.AlignVCenter
                            }
                        }

                        Row {
                            id: rightSide
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 8

                            Text {
                                font.family: Services.Fonts.family
                                width: 24
                                height: 24
                                verticalAlignment: Text.AlignVCenter
                                horizontalAlignment: Text.AlignRight
                                text: root.pillOn(grp.g.group) ? "On" : "Off"
                                font.pixelSize: 12
                                font.bold: true
                                color: root.pillOn(grp.g.group)
                                    ? Services.Colors.accent
                                    : Services.Colors.textMuted

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
                                color: root.pillOn(grp.g.group)
                                    ? Services.Colors.accent
                                    : Services.Colors.surface

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Services.Motion.effectsFast
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                    }
                                }

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: root.pillOn(grp.g.group)
                                        ? parent.width - width - 3 : 3
                                    width: 18
                                    height: 18
                                    radius: 9
                                    color: root.pillOn(grp.g.group)
                                        ? Services.Colors.background
                                        : Services.Colors.textMuted

                                    Behavior on color {
                                        ColorAnimation {
                                            duration: Services.Motion.effectsFast
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                        }
                                    }

                                    // knob throw — the pop spring overshoots
                                    // the end stop and snaps back: the M3
                                    // switch bounce, felt not just seen
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
                                    onClicked: root.pillTap(grp.g.group)
                                }
                            }

                            Row {
                                spacing: 6

                                Repeater {
                                    model: root.speeds

                                    delegate: Rectangle {
                                        readonly property bool selected:
                                            root.chipOn(grp.g.group, modelData.v)
                                        height: 28
                                        radius: 14
                                        width: speedLabel.width + 26
                                        color: selected
                                            ? Services.Colors.accent
                                            : (speedMouse.containsMouse
                                                ? Services.Colors.surfaceAlt
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
                                            id: speedLabel
                                            anchors.centerIn: parent
                                            text: modelData.label
                                            font.pixelSize: 12
                                            font.bold: parent.selected
                                            color: parent.selected
                                                ? Services.Colors.background
                                                : Services.Colors.textMuted

                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: Services.Motion.effectsFast
                                                    easing.type: Easing.BezierSpline
                                                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                                }
                                            }
                                        }

                                        MouseArea {
                                            id: speedMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked:
                                                root.setSpeed(grp.g.group, modelData.v)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
