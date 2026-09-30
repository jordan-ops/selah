import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Expanding dropdown — the new `dropdown` row type, for lists too long
// for chips (layouts, fonts). The trigger sits where the chips would;
// opening it grows the ROW (extraHeight) and drops a scrollable panel
// under the trigger, so deep-linked rows still land on screen and the
// window's own scrolling does the rest.
//
//   source "hypr"    — options[] apply through hyprctl eval, current
//                      value read from hyprctl getoption.
//   source "fonts"   — families scanned from ~/.local/share/fonts +
//                      /usr/share/fonts (path-filtered fc-list output),
//                      applied through scripts/set-font.sh.
Item {
    id: root

    property var e: null
    property bool open: false
    readonly property bool isFonts: e && e.source === "fonts"
    readonly property bool isHypr: e && e.source === "hypr"

    property var families: []
    property string current: ""

    readonly property var options: isHypr ? (e.options || []) : []
    readonly property var shownList: {
        if (!isFonts) return options
        const q = searchField.text.trim().toLowerCase()
        if (q === "") return families
        return families.filter(f => f.toLowerCase().includes(q))
    }
    readonly property string currentLabel: {
        if (isFonts) return current !== "" ? current : "—"
        if (current === "") return "—"
        const hit = options.find(o => String(o.value) === current)
        return hit ? hit.label : current
    }

    // row growth: panel + breathing room; the delegate adds this to 64
    readonly property real panelH: open ? panel.implicitHeight : 0
    readonly property real extraHeight: open ? panelH + 6 : 0

    width: 244
    height: 30 + extraHeight

    function toggle() {
        root.open = !root.open
        if (root.open && isFonts && families.length === 0) scanProc.running = true
        if (root.open && isHypr) readProc.running = true
    }

    function pick(value) {
        root.open = false
        if (isHypr) {
            // Apply/Revert baseline: the option's value before this pick
            // (hyprChanged drops no-op changes on its own)
            Services.SettingsApp.hyprChanged(e.hyprKey,
                String(root.current), String(value))
            root.current = String(value)
            writeProc.command = ["hyprctl", "eval",
                Services.SettingsCatalog.hyprEval(e.hyprKey,
                                                   Services.SettingsCatalog.hyprLuaValue(String(value)))]
            writeProc.running = true
        } else {
            root.current = String(value)
            fontProc.command = [Quickshell.shellDir + "/scripts/set-font.sh", String(value)]
            fontProc.running = true
        }
    }

    Component.onCompleted: {
        if (isHypr) readProc.running = true
        if (isFonts) { scanProc.running = true; currentProc.running = true }
    }

    // Revert evaled baselines back — re-read so the closed button shows
    // the restored option value
    Connections {
        target: Services.SettingsApp
        function onRevertDone() {
            if (root.isHypr && !readProc.running) readProc.running = true
        }
    }

    Process {
        id: readProc
        command: ["hyprctl", "getoption", root.e ? root.e.hyprKey : ""]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = Services.SettingsCatalog.hyprParse(text)
                if (v !== null && v !== undefined) root.current = String(v)
            }
        }
    }
    Process { id: writeProc }

    // fc-list's dir argument is a FAMILY pattern, not a path filter — it
    // matches nothing. Filter on %{file} instead: families whose files
    // live in the two font dirs the spec names.
    Process {
        id: scanProc
        command: ["bash", "-c", "fc-list --format '%{file}\t%{family[0]}\n'"]
        stdout: StdioCollector {
            onStreamFinished: {
                const roots = [Quickshell.env("HOME") + "/.local/share/fonts",
                               "/usr/share/fonts"]
                const list = []
                text.split("\n").forEach(line => {
                    const tab = line.indexOf("\t")
                    if (tab < 0) return
                    const file = line.slice(0, tab)
                    const family = line.slice(tab + 1).trim()
                    if (family === "") return
                    if (list.indexOf(family) >= 0) return
                    if (roots.some(r => file.startsWith(r + "/"))) list.push(family)
                })
                root.families = list.sort((a, b) => a.localeCompare(b))
            }
        }
    }

    Process {
        id: currentProc
        command: ["gsettings", "get", "org.gnome.desktop.interface", "font-name"]
        stdout: StdioCollector {
            onStreamFinished: {
                // "'DejaVu Sans 11'" — strip quotes, drop the trailing size
                let t = text.trim().replace(/^'|"$/g, "")
                const m = t.match(/^(.*)\s+\d+$/)
                if (m) t = m[1]
                root.current = t
            }
        }
    }

    // after set-font.sh: re-read what actually landed
    Process {
        id: fontProc
        onExited: currentProc.running = true
    }

    // trigger — chips-shaped, right aligned
    Rectangle {
        id: trigger
        anchors.right: parent.right
        y: 0
        width: Math.min(root.width, triggerRow.implicitWidth + 30)
        height: 30
        radius: 15
        color: root.open ? Services.Colors.accent : Services.Colors.surface

        Behavior on color {
            ColorAnimation {
                duration: Services.Motion.effectsFast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.emphasizedDecelerate
            }
        }

        Row {
            id: triggerRow
            anchors.centerIn: parent
            spacing: 8

            Text {
                font.family: Services.Fonts.family
                anchors.verticalCenter: parent.verticalCenter
                text: root.currentLabel
                font.pixelSize: 12
                font.bold: true
                elide: Text.ElideRight
                width: Math.min(implicitWidth, 150)
                color: root.open ? Services.Colors.background : Services.Colors.text

                Behavior on color {
                    ColorAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }
            }
            Text {
                font.family: Services.Fonts.family
                anchors.verticalCenter: parent.verticalCenter
                text: "󰁸"     // chevron-down
                font.pixelSize: 12
                color: root.open ? Services.Colors.background : Services.Colors.textMuted

                Behavior on color {
                    ColorAnimation {
                        duration: Services.Motion.effectsFast
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }
            }
        }

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggle()
        }
    }

    // expanded panel — grows under the trigger; the delegate row has
    // already made room via extraHeight. Entrance/exit: fades + a small
    // top-anchored scale so it reads as dropping out of the trigger;
    // `visible` rides opacity so the exit animation gets to play before
    // the panel disappears.
    Rectangle {
        id: panel
        anchors.left: parent.left
        anchors.right: parent.right
        y: 34
        opacity: root.open ? 1 : 0
        visible: opacity > 0.01
        scale: root.open ? 1 : 0.94
        transformOrigin: Item.Top
        implicitHeight: contentCol.implicitHeight + 8
        height: implicitHeight
        radius: 10
        color: Services.Colors.background
        border.color: Services.Colors.low
        border.width: 1
        clip: true

        Behavior on opacity {
            NumberAnimation {
                duration: Services.Motion.effects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.emphasizedDecelerate
            }
        }
        Behavior on scale {
            SpringAnimation { spring: Services.Motion.spatialFastSpring; damping: Services.Motion.spatialFastDamping }
        }

        Column {
            id: contentCol
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 4
            spacing: 4

            // filter box — only for the long list (fonts)
            Item {
                visible: root.isFonts && root.families.length > 30
                width: parent.width
                height: visible ? 26 : 0

                Rectangle {
                    anchors.fill: parent
                    radius: 13
                    color: Services.Colors.surface
                }
                TextInput {
                    font.family: Services.Fonts.family
                    id: searchField
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    clip: true
                    color: Services.Colors.text
                    font.pixelSize: 12
                    selectionColor: Services.Colors.accent
                    Text {
                        font.family: Services.Fonts.family
                        visible: searchField.text === ""
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Filter fonts…"
                        color: Services.Colors.textMuted
                        font.pixelSize: 12
                    }
                }
            }

            Flickable {
                width: parent.width
                height: Math.min(200, Math.max(28, root.shownList.length * 28 + 4))
                contentHeight: root.shownList.length * 28 + 4
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: root.shownList

                        delegate: Rectangle {
                            readonly property bool selected: {
                                if (root.isFonts) return modelData === root.current
                                return String(modelData.value) === root.current
                            }
                            width: parent.width
                            height: 26
                            radius: 7
                            color: selected ? Services.Colors.surfaceAlt
                                 : optionMouse.containsMouse ? Services.Colors.surface : "transparent"

                            Behavior on color {
                                ColorAnimation {
                                    duration: Services.Motion.effectsFast
                                    easing.type: Easing.BezierSpline
                                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                }
                            }

                            Text {
                                font.family: Services.Fonts.family
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 20
                                text: root.isFonts ? modelData : modelData.label
                                font.pixelSize: 12
                                font.bold: selected
                                elide: Text.ElideRight
                                color: selected ? Services.Colors.accent : Services.Colors.text

                                Behavior on color {
                                    ColorAnimation {
                                        duration: Services.Motion.effectsFast
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                    }
                                }
                            }

                            MouseArea {
                                id: optionMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.pick(root.isFonts ? modelData : modelData.value)
                            }
                        }
                    }

                    Text {
                        font.family: Services.Fonts.family
                        visible: root.shownList.length === 0
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "No match"
                        font.pixelSize: 11
                        color: Services.Colors.textMuted
                    }
                }
            }
        }
    }
}
