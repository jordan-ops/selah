import QtQuick
import "./services" as Services

// Rotary knob — the renderer's `knob` control (audio volume rows). A
// DUMB dial: it owns no backend — the row feeds `value` in and listens
// for moved(v) (throttled live write) and committed(v) (final write on
// release, or a wheel step). 270° sweep θ = -135° + 270°·t: an accent
// value arc over the slider's 15%-text track, a pointer capsule
// orbiting the rim, the rounded value in the center.
//
// Drag is ROTATIONAL — each move contributes its angle delta unwrapped
// at ±180°, so a spin through 12/6 o'clock never jumps (the classic
// atan2 discontinuity). The wheel steps ±step. Press squishes to 0.96
// and pops back on release; the readout springs to a wheel step with
// the same pop (popSpring) but tracks the finger exactly while turning
// (Behavior disabled during the drag — no lag under the hand).
Item {
    id: root

    property real value: 0
    property real min: 0
    property real max: 100
    property real step: 1
    property string suffix: ""
    property real size: 52

    readonly property real span: Math.max(1, max - min)

    property real pending: 0
    property bool dragging: false
    // writable on purpose: Behavior can only be installed on a writable
    // property (Qt errors "…is a read-only property" otherwise)
    property real shown: dragging ? pending : value
    Behavior on shown {
        enabled: !root.dragging
        SpringAnimation { spring: Services.Motion.popSpring; damping: Services.Motion.popDamping }
    }
    readonly property real t: (shown - min) / span   // 0..1, at the finger or after the spring

    signal moved(real v)
    signal committed(real v)

    implicitWidth: size
    implicitHeight: size

    function snap(v) {
        return Math.max(min, Math.min(max, Math.round(v / step) * step))
    }

    function commit(v) {
        const nv = snap(v)
        pending = nv
        value = nv
        dragging = false
        committed(nv)
    }

    // press feedback — squish immediately, spring back (spatial → spring)
    scale: press.pressed ? 0.96 : 1
    Behavior on scale {
        enabled: !press.pressed
        SpringAnimation { spring: Services.Motion.popSpring; damping: Services.Motion.popDamping }
    }

    // track + value arc — same recipes as the slider (text @15%, accent)
    Canvas {
        id: dial
        anchors.fill: parent
        readonly property real tv: root.t
        readonly property var acc: Services.Colors.accent
        readonly property var txt: Services.Colors.text
        onTvChanged: requestPaint()
        onAccChanged: requestPaint()
        onTxtChanged: requestPaint()
        onWidthChanged: requestPaint()

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            const cx = width / 2
            const cy = height / 2
            const lw = Math.max(3, Math.round(root.size * 0.075))
            const r = width / 2 - lw / 2 - 1
            const start = 135 * Math.PI / 180     // bottom-left = min
            const full = 270 * Math.PI / 180
            ctx.lineWidth = lw
            ctx.lineCap = "round"
            ctx.strokeStyle = Qt.rgba(txt.r, txt.g, txt.b, 0.15)
            ctx.beginPath()
            ctx.arc(cx, cy, r, start, start + full, false)
            ctx.stroke()
            if (tv > 0.005) {
                ctx.strokeStyle = acc
                ctx.beginPath()
                ctx.arc(cx, cy, r, start, start + full * Math.min(1, tv), false)
                ctx.stroke()
            }
        }
    }

    // pointer capsule — orbits the knob center on the same t, so arc,
    // pointer and number stay one object while the spring settles
    Item {
        id: orbit
        anchors.fill: parent
        transformOrigin: Item.Center
        rotation: -135 + 270 * Math.max(0, Math.min(1, root.t))

        Rectangle {
            width: Math.max(3, Math.round(root.size * 0.065))
            height: Math.max(8, Math.round(root.size * 0.17))
            radius: width / 2
            color: Services.Colors.accent
            x: (orbit.width - width) / 2
            y: Math.round(root.size * 0.085)
        }
    }

    Text {
        font.family: Services.Fonts.family
        anchors.centerIn: parent
        text: Math.round(root.shown) + root.suffix
        color: Services.Colors.textMuted
        font.pixelSize: Math.max(9, Math.round(root.size * 0.2))
        font.bold: true
    }

    MouseArea {
        id: press
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true     // a list pan must never hijack a turn
        cursorShape: Qt.PointingHandCursor
        property real lastA: 0
        property real accum: 0
        property real base: 0

        function ang(x, y) {
            return Math.atan2(y - root.height / 2, x - root.width / 2) * 180 / Math.PI
        }

        onPressed: mouse => {
            base = root.value
            root.pending = root.value
            accum = 0
            lastA = ang(mouse.x, mouse.y)
            root.dragging = true
        }
        onPositionChanged: mouse => {
            if (!pressed) return
            const a = ang(mouse.x, mouse.y)
            let d = a - lastA
            if (d > 180) d -= 360
            else if (d < -180) d += 360
            lastA = a
            accum += d
            const nv = root.snap(base + accum * root.span / 270)
            if (nv !== root.pending) {
                root.pending = nv
                root.moved(nv)
            }
        }
        onReleased: root.commit(root.pending)
        onCanceled: root.commit(root.pending)
        onWheel: ev => {
            const d = ev.angleDelta.y
            if (d === 0) return
            root.value = root.snap(root.value + (d > 0 ? root.step : -root.step))
            root.pending = root.value
            root.committed(root.value)
            ev.accepted = true
        }
    }
}
