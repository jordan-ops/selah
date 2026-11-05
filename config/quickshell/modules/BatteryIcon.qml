import QtQuick
import QtQuick.Shapes
import "../services" as Services

// iOS-style battery (the iOS 27 status-bar look): a borderless capsule
// split between the level fill and a muted track — no outline, no
// terminal nub, the colour break itself carries the level. Replaces the
// old open-arc ring in the bar (the Control Center hero still uses
// BatteryRing).
//
// bar.batteryText puts the percentage INSIDE the body (iOS 16+ style)
// rather than next to the icon: the number flips between the fill colour
// and `background` (the surface the icon sits on) so it stays legible
// whether or not the fill has reached it. showPercent follows the
// setting but can be pinned by the caller.
//
// No battery on this machine (VM/desktop) → the whole icon is hidden,
// which the bar's Row skips in its width math (same contract the ring's
// arc had).
Item {
    id: root
    height: 12
    // the number needs a wider body than the bare track does
    width: showPercent ? 26 : 24

    property real level: Services.Battery.percent
    property bool charging: Services.Battery.charging
    property bool showPercent: Services.Settings.barBatteryText
    // the surface behind the body — the % cuts out of the fill with this
    // colour once the fill has passed under it (status chip in the wide
    // row, the pill itself in the compact capsule)
    property color background: Services.Colors.surface

    visible: Services.Battery.hasBattery

    // the unfilled half of the capsule: the same muted grey the wired
    // wifi glyph uses, so "not this much" reads the same everywhere
    readonly property color trackColor: Services.Colors.textMuted

    property color fillColor: {
        if (charging) return Services.Colors.accent
        if (level <= 15) return Services.Colors.critical
        if (level <= 30) return "#fdd663"
        return Services.Colors.text
    }

    Behavior on fillColor {
        ColorAnimation {
            duration: Services.Motion.medium2
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Services.Motion.standardCurve
        }
    }

    // fill's right edge in body coordinates — where the % below splits.
    // Spring-animated (the Behaviour below), so the % halves follow the
    // moving edge instead of snapping ahead of it.
    property real fillW: body.width * Math.min(100, Math.max(0, level)) / 100
    readonly property real fillRight: Math.max(0, Math.min(fillW, body.width))

    Behavior on fillW {
        SpringAnimation {
            spring: Services.Motion.spatialSlowSpring
            damping: Services.Motion.spatialSlowDamping
        }
    }

    // the fill as one path: rounded on the left (it wears the track's
    // cap) with a hard vertical right edge at fillRight. A plain
    // Rectangle can only round BOTH ends, and Rectangle's clip ignores
    // the radius here, so a rect would poke square corners out of the
    // capsule at low levels.
    function fillPath(x) {
        const h = body.height
        const r = h / 2
        return "M " + x.toFixed(2) + " 0 L " + r + " 0"
             + " A " + r + " " + r + " 0 0 0 0 " + r
             + " L 0 " + (h - r)
             + " A " + r + " " + r + " 0 0 0 " + r + " " + h
             + " L " + x.toFixed(2) + " " + h + " Z"
    }
    readonly property string fillPathData: fillRight > 0.5 ? fillPath(fillRight) : ""

    // ---- charge pulse: the visual replacement for the removed
    // "Charging" notification (same wave the ring used to run). The
    // rising edge of charging pops the icon once — skipped under
    // reduced motion, the fill colour flipping to the accent already
    // tells you it's plugged in.
    SequentialAnimation {
        id: chargePulseAnim
        NumberAnimation {
            target: root; property: "scale"
            to: 1.18; duration: 320
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Services.Motion.emphasizedDecelerate
        }
        NumberAnimation {
            target: root; property: "scale"
            to: 1; duration: 380
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Services.Motion.standardCurve
        }
    }
    onChargingChanged: {
        if (charging && Services.Motion.motionOn)
            chargePulseAnim.restart()
    }

    // the capsule: track colour everywhere, with the level fill drawn
    // inside it as the rounded-left / flat-right path above
    Rectangle {
        id: body
        anchors.fill: parent
        radius: height / 2
        color: root.trackColor

        Shape {
            anchors.fill: parent

            ShapePath {
                fillColor: root.fillColor
                strokeColor: "transparent"

                PathSvg { path: root.fillPathData }
            }
        }
    }

    // the % inside the body — only when the toggle is on (and only when
    // there is a battery to report, since the whole icon hides otherwise).
    // Drawn as TWO clipped halves that meet exactly at the fill's right
    // edge: the part sitting on the fill cuts out in `background`, the
    // part over the track paints in the fill colour. Flipping the
    // whole number at once instead would either hide its tail on the
    // track side or paint fill-on-fill at mid levels — and it would need
    // text metrics to guess which case it is in.
    Item {
        id: pctOverFill
        visible: root.showPercent && width > 0.5
        x: body.x
        y: body.y
        width: Math.min(root.fillRight, body.width)
        height: body.height
        clip: true

        Text {
            x: body.width / 2 - width / 2
            y: body.height / 2 - height / 2
            text: root.level
            font.family: Services.Fonts.family
            font.pixelSize: 9
            font.bold: true
            color: root.background
        }
    }

    Item {
        id: pctOverEmpty
        visible: root.showPercent && width > 0.5
        x: body.x + Math.min(root.fillRight, body.width)
        y: body.y
        width: Math.max(0, body.width - root.fillRight)
        height: body.height
        clip: true

        Text {
            // body-relative placement, shifted into this window's coords
            x: body.width / 2 - width / 2 - root.fillRight
            y: body.height / 2 - height / 2
            text: root.level
            font.family: Services.Fonts.family
            font.pixelSize: 9
            font.bold: true
            color: root.fillColor

            Behavior on color {
                ColorAnimation {
                    duration: Services.Motion.medium2
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.standardCurve
                }
            }
        }
    }
}
