import QtQuick
import Quickshell.Io
import "./services" as Services

// Right-aligned slider for one Hyprland numeric option — the renderer's
// `slider` row type. Same track/fill/handle language as QSSlider and
// the window's chips; reads the live value once with hyprctl getoption,
// writes ONLY when the drag ends (omasettings' NumberRow rule: a write
// takes a state refresh to come back, so mid-drag writes fight the read).
// `e.scale` maps display units to the stored value (percent rows show
// 50–100 while hyprland holds 0.5–1.0).
//
// `e.hyprKeys[]` commits ONE value to several options at once (scroll
// speed moves `input:scroll_factor` and `input:touchpad:scroll_factor`
// together — the page is Mouse & Touchpad, one feel, one control). Each
// key keeps its own revert baseline, reads ride in one bash process
// split on __qs_seg__, and `e.persistKey` records the number in
// settings.json so SettingsApp's start-of-session reapply can restore
// both sides — hyprctl eval alone is runtime-only.
Item {
    id: root

    property var e: null
    readonly property var keys: !e ? [] : (e.hyprKeys || [e.hyprKey])
    readonly property real sc: e && e.scale !== undefined ? Number(e.scale) : 1
    readonly property real min: e && e.min !== undefined ? Number(e.min) : 0
    readonly property real max: e && e.max !== undefined ? Number(e.max) : 100
    readonly property real step: e && e.step !== undefined ? Number(e.step) : 1
    readonly property string suffix: e && e.suffix ? e.suffix : ""

    // display precision follows the step: whole numbers stay whole,
    // 0.1 rows show a tenth instead of rounding 1.2 down to "1"
    readonly property int dec: step >= 1 ? 0 : (step >= 0.1 ? 1 : 2)

    // live = what hyprland holds (in display units); pending = where the
    // finger is. The row shows pending while dragging, live otherwise.
    // lives = the raw per-key stored values (revert baselines).
    property real live: min
    property var lives: []
    property real pending: min
    property bool dragging: false
    readonly property real shown: dragging ? pending : live
    readonly property real extraHeight: 0   // sliders never grow the row

    width: 214
    height: 30

    function clamp(v) { return Math.max(min, Math.min(max, v)) }
    function snap(v) { return clamp(Math.round(v / step) * step) }

    function commit(next) {
        const wanted = snap(next)
        pending = wanted
        dragging = false
        const stored = Number((wanted * sc).toFixed(3))
        // Apply/Revert baseline: the stored value before this commit
        // (hyprChanged drops no-op changes on its own) — one baseline
        // per key so a multi-key row reverts on every side it touched
        for (let i = 0; i < root.keys.length; i++) {
            const before = i < root.lives.length
                ? Number(root.lives[i].toFixed(3))
                : Number((root.live * root.sc).toFixed(3))
            Services.SettingsApp.hyprChanged(root.keys[i], before, stored)
        }
        if (e.persistKey) Services.Settings.set(e.persistKey, stored)
        writeProc.command = root.keys.length <= 1
            ? ["hyprctl", "eval",
               Services.SettingsCatalog.hyprEval(root.keys[0],
                   Services.SettingsCatalog.hyprLuaValue(stored))]
            : ["bash", "-c", root.keys.map(k =>
                   "hyprctl eval '" + Services.SettingsCatalog.hyprEval(k,
                       Services.SettingsCatalog.hyprLuaValue(stored)) + "'"
               ).join("; ")]
        writeProc.running = true
        live = wanted
        lives = root.keys.map(() => stored)
    }

    Component.onCompleted: readProc.running = true

    // Revert evaled baselines back inside hyprland — re-read so the
    // handle shows the restored value, not the reverted-away one
    Connections {
        target: Services.SettingsApp
        function onRevertDone() { if (!readProc.running) readProc.running = true }
    }

    Process {
        id: readProc
        // one option per key; multi-key rows join getoption outputs on
        // a marker line so a single run feeds every baseline
        command: root.keys.length === 0 ? ["hyprctl", "getoption", ""]
            : root.keys.length === 1 ? ["hyprctl", "getoption", root.keys[0]]
            : ["bash", "-c", root.keys.map(k =>
                  "hyprctl getoption " + k + "; echo __qs_seg__").join("; ")]
        stdout: StdioCollector {
            onStreamFinished: {
                const segs = root.keys.length <= 1 ? [text] : String(text).split("__qs_seg__")
                const lives = []
                let primary = null
                for (let i = 0; i < root.keys.length && i < segs.length; i++) {
                    // segments after the first start with a newline —
                    // hyprParse reads line 0, so trim before parsing
                    const v = Services.SettingsCatalog.hyprParse(String(segs[i]).trim())
                    if (typeof v === "number") {
                        lives.push(v)
                        if (i === 0) primary = v
                    }
                }
                root.lives = lives
                if (primary !== null) root.live = root.clamp(primary / root.sc)
            }
        }
    }
    Process { id: writeProc }

    Row {
        anchors.fill: parent
        spacing: 10

        // track — 6px pill, accent fill, 14px handle (M3 slider)
        Item {
            id: trackBox
            width: parent.width - readout.width - parent.spacing
            height: parent.height

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.15)

                Rectangle {
                    width: track.width * (root.shown - root.min) / Math.max(1, root.max - root.min)
                    height: parent.height
                    radius: 3
                    color: Services.Colors.accent
                    Behavior on width { SpringAnimation { spring: Services.Motion.bounceSpring; damping: Services.Motion.bounceDamping } }
                }

                Rectangle {
                    id: handle
                    x: (track.width - width) * (root.shown - root.min) / Math.max(1, root.max - root.min)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    radius: 7
                    color: Services.Colors.accent
                    border.color: Services.Colors.background
                    border.width: 2
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8          // generous grab zone
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => beginDrag(mouse.x)
                    onPositionChanged: mouse => { if (pressed) beginDrag(mouse.x) }
                    onReleased: root.commit(root.pending)

                    function beginDrag(x) {
                        const norm = Math.max(0, Math.min(1, x / track.width))
                        root.dragging = true
                        root.pending = root.snap(root.min + norm * (root.max - root.min))
                    }
                }
            }
        }

        Text {
            font.family: Services.Fonts.family
            id: readout
            anchors.verticalCenter: parent.verticalCenter
            width: 58
            horizontalAlignment: Text.AlignRight
            text: root.shown.toFixed(root.dec) + (root.suffix !== "" ? " " + root.suffix : "")
            color: Services.Colors.textMuted
            font.pixelSize: 12
            font.bold: true
        }
    }
}
