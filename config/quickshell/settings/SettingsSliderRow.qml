import QtQuick
import Quickshell.Io
import "../services" as Services

// Right-aligned slider for one Hyprland numeric option — the renderer's
// `slider` row type. The control itself is SettingsFrostSlider (the
// widget studio's M3Slider behind a display-unit facade), so the
// settings window and the widget editor share one slider language;
// reads the live value once with hyprctl getoption, writes ONLY when
// the drag ends (omasettings' NumberRow rule: a write takes a state
// refresh to come back, so mid-drag writes fight the read). Until that
// first read lands the control stays invisible — no flash of `min`
// that then jumps to the real value.
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
    // ready = the first hyprctl read has landed (async) — until then
    // the control renders at 0 opacity instead of flashing `min`.
    property real live: min
    property var lives: []
    property real pending: min
    property bool dragging: false
    property bool ready: false
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
                // first read landed — reveal the slider (also covers a
                // parse miss: show the clamped default rather than an
                // invisible row that never comes back)
                root.ready = true
            }
        }
    }
    Process { id: writeProc }

    // SettingsFrostSlider (the studio's M3Slider) in the same track
    // area the hand-rolled slider had — same 214x30 outer footprint,
    // same readout on the right; moved = live drag preview (updates
    // `pending`), committed = release → the row's write path
    Row {
        anchors.fill: parent
        spacing: 10

        SettingsFrostSlider {
            id: frost
            width: parent.width - readout.width - parent.spacing
            height: parent.height
            value: root.shown
            from: root.min
            to: root.max
            step: root.step
            suffix: root.suffix
            disabled: !root.enabled || !root.ready
            onMoved: v => {
                root.dragging = true
                root.pending = root.snap(v)
            }
            onCommitted: v => root.commit(v)
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

    // Before the first hyprctl read lands, the whole control zone stays
    // invisible (layout is reserved, so nothing shifts when it appears)
    opacity: root.ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }
}
