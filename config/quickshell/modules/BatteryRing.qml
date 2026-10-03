import QtQuick
import "../services" as Services

// iPhone-style battery ring, per the mockup: an open arc (gap at the top)
// whose fill is the battery level, the nerd-font network glyph in the
// middle, and — when bar.batteryText is toggled on — the bare percentage
// sitting in the top gap. Clicking anywhere on it opens the control
// center, same as the status chip around it.
Item {
    id: root
    width: 24
    height: 24

    // In the bar (capsule / status chip) a ring click opens the control
    // center; the control center panel itself embeds a ring, and that one
    // must not close the very panel it lives in — set false there.
    property bool clickOpensCC: true

    readonly property int level: Services.Battery.percent
    readonly property bool charging: Services.Battery.charging

    // the C opens upward: gap spans -140°..-40° (0° = right, clockwise),
    // level fills counter-clockwise from the gap's left edge so a low
    // battery shows red at the top-left, exactly like the mockup
    readonly property real gapDeg: 100
    readonly property real sweepDeg: 360 - gapDeg
    readonly property real startDeg: -90 - gapDeg / 2

    property color fillColor: {
        if (charging) return Services.Colors.accent
        if (level <= 15) return Services.Colors.critical
        if (level <= 30) return "#fdd663"
        return Services.Colors.text
    }

    // ---- charge pulse: the visual replacement for the removed
    // "Charging" notification. Charging's rising edge runs one 0→1→0
    // wave (~700ms): the whole chip pops slightly and the canvas lays a
    // thickened fill + accent halo over the arc (painted from this
    // value). Skipped under reduced motion — the fill colour flipping to
    // the accent already tells you it's plugged in.
    property real chargePulse: 0
    scale: 1 + chargePulse * 0.15

    SequentialAnimation {
        id: chargePulseAnim
        NumberAnimation {
            target: root; property: "chargePulse"
            from: 0; to: 1; duration: 320
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Services.Motion.emphasizedDecelerate
        }
        NumberAnimation {
            target: root; property: "chargePulse"
            from: 1; to: 0; duration: 380
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Services.Motion.standardCurve
        }
    }
    onChargingChanged: {
        if (charging && Services.Motion.motionOn)
            chargePulseAnim.restart()
    }

    Canvas {
        id: canvas
        anchors.fill: parent
        contextType: "2d"
        // no battery on this machine (VM, desktop): no ring, no level —
        // the centre glyph below stays so the pill keeps its network icon
        visible: Services.Battery.hasBattery

        onPaint: {
            const ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)

            const cx = width / 2
            const cy = height / 2
            const sw = 2.5
            const r = width / 2 - sw / 2 - 0.5
            const rad = d => d * Math.PI / 180
            const s = rad(root.startDeg)

            ctx.lineCap = "round"
            ctx.lineWidth = sw

            // dim track — the open C (gap left open at the top)
            const t = Services.Colors.text
            ctx.strokeStyle = Qt.rgba(t.r, t.g, t.b, 0.22)
            ctx.beginPath()
            ctx.arc(cx, cy, r, s, rad(root.startDeg + root.sweepDeg), true)
            ctx.stroke()

            // level fill — counter-clockwise from the gap's left edge
            if (root.level > 0) {
                ctx.strokeStyle = root.fillColor
                ctx.beginPath()
                ctx.arc(cx, cy, r, s, rad(root.startDeg - root.sweepDeg * root.level / 100), true)
                ctx.stroke()
            }

            // charge pulse layer — rides ON TOP of the static strokes
            // while chargePulse waves (thickened fill + accent halo),
            // so nothing else repaints differently mid-pulse
            if (root.chargePulse > 0.01 && root.level > 0) {
                const arc = () => {
                    ctx.beginPath()
                    ctx.arc(cx, cy, r, s, rad(root.startDeg - root.sweepDeg * root.level / 100), true)
                }
                ctx.lineWidth = sw + root.chargePulse * 3
                ctx.strokeStyle = root.fillColor
                arc()
                ctx.stroke()

                const a = Services.Colors.accent
                ctx.lineWidth = sw + 6
                ctx.strokeStyle = Qt.rgba(a.r, a.g, a.b, 0.35 * root.chargePulse)
                arc()
                ctx.stroke()
            }
        }
    }

    // repaint triggers: level, battery color state, theme switches,
    // and the charge pulse wave above
    onLevelChanged: canvas.requestPaint()
    onFillColorChanged: canvas.requestPaint()
    onChargePulseChanged: canvas.requestPaint()
    Component.onCompleted: canvas.requestPaint()
    Connections {
        target: Services.Colors
        function onTextChanged() { canvas.requestPaint() }
    }

    // bare number in the gap — only once bar.batteryText is toggled on
    // (and only when there is a battery to report)
    Text {
        font.family: Services.Fonts.family
        visible: Services.Settings.barBatteryText && Services.Battery.hasBattery
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: -2
        text: root.level
        font.pixelSize: 10
        font.bold: true
        color: Services.Colors.text
    }

    // nerd-font network glyph in the center — Network.glyph picks the
    // state (wifi / connected-wired / offline), nudged down to clear the
    // number
    Text {
        font.family: Services.Fonts.family
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: 2
        text: Services.Network.glyph
        font.pixelSize: 12
        color: Services.Network.connected ? Services.Colors.text : Services.Colors.textMuted
        opacity: Services.Network.connected ? 1 : 0.55
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.clickOpensCC) Services.ControlCenter.toggle()
    }
}
