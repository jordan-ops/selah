import QtQuick
import "widgets"
import "./services" as Services

// Settings-facing adapter over widgets/M3Slider.qml — the "frost
// slider" the widget studio uses (thick rounded track, pill handle,
// floating value bubble while pressed). It exists so the settings rows
// and the widget editor share ONE slider language, and because the two
// sides speak different units: M3Slider moves a 0..1 progress, the
// settings rows speak display units (min/max/step/suffix).
//
// Facade (all display units):
//   value    — the number the row shows; drives the handle
//   from/to  — the value range (the row's min/max)
//   step     — increment; M3Slider quantises drags to it itself via
//              stepCount (span/step + 1), so the handle can't land
//              between steps and commit never jumps on release
//   suffix   — appended to the floating bubble text ("px", "%")
//   disabled — dims the slider and blocks input (rows use this while a
//              dependent switch is off, and before the first async read)
//   showValueLabel — the M3 bubble; false when the container can't give
//              ~32px above the handle (floatGap-tight bars)
//   pressed  — live press state (read-only)
//   moved(v)    — fired live during drag, already step-snapped by M3Slider
//   committed(v)— fired on release (and on wheel)
//
// Colours are passed EXPLICITLY from services/Colors (the settings
// palette) instead of M3Slider's own defaults (widgets/Colors), so
// the rows follow the settings theme like every other control.
//
// Height contract: implicitHeight 32 (M3Slider's default). The rows
// give it the same 30px control height the old hand-rolled slider had,
// so the row footprint (and the window's ctlZone reservation) is
// unchanged.
Item {
    id: root

    property real value: 0
    property real from: 0
    property real to: 100
    property real step: 0
    property string suffix: ""
    property bool disabled: false
    // M3's floating value bubble (press-only, ~900ms linger). On by
    // default like the studio slider; callers whose container can't
    // spare ~32px above the handle (the bar OSD's pill, floatGap 8)
    // turn it off and show their own readout instead.
    property bool showValueLabel: true
    // live press state — the OSD holds its auto-hide timer while held
    readonly property bool pressed: slider.pressed

    signal moved(real v)
    signal committed(real v)

    implicitWidth: 200
    implicitHeight: 32

    opacity: root.disabled ? 0.5 : 1
    Behavior on opacity {
        NumberAnimation { duration: M3Motion.effects.fastDuration }
    }

    readonly property real _span: Math.max(0, root.to - root.from)
    // stepCount for M3Slider's quantiser: one step across the whole span
    // plus the ends. 0 (or 1) = continuous, no snapping.
    readonly property int _steps: root.step > 0
        ? Math.round(root._span / root.step) + 1 : 0
    // bubble/readout precision follows the step: whole numbers stay
    // whole, 0.1 rows show a tenth instead of rounding 1.2 down to "1"
    readonly property int _dec: root.step >= 1 ? 0 : (root.step >= 0.1 ? 1 : 2)

    function _denorm(p) { return root.from + p * root._span }

    // value → slider progress. M3Slider's drag writes `progress`
    // imperatively (which would BREAK a binding on first touch and never
    // revive), so the sync runs from change handlers instead: on every
    // external value change (initial read, revertDone re-read, another
    // key of a multi-key row) the handle is re-positioned.
    function _sync() {
        slider.progress = root._span > 0
            ? Math.max(0, Math.min(1, (root.value - root.from) / root._span))
            : 0
    }
    onValueChanged: _sync()
    onFromChanged: _sync()
    onToChanged: _sync()
    Component.onCompleted: _sync()

    M3Slider {
        id: slider
        anchors.fill: parent
        from: 0
        to: 1
        stepCount: root._steps
        interactive: !root.disabled
        showValueLabel: root.showValueLabel
        valueText: root._denorm(slider.value).toFixed(root._dec)
            + (root.suffix !== "" ? " " + root.suffix : "")

        // settings palette, not the widget layer's own defaults:
        // accent fill + accent handle, a surface variant for the
        // remaining track, muted text for the icon/bubble glyph colour
        activeColor:   Services.Colors.accent
        handleColor:   Services.Colors.accent
        inactiveColor: Services.Colors.surfaceAlt
        iconColor:     Services.Colors.textMuted

        onMoved: p => root.moved(root._denorm(p))
        onCommitted: p => root.committed(root._denorm(p))
    }
}
