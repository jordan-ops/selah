import QtQuick
import QtQuick.Effects
import Quickshell
import "../services" as Services

// The giant time renderer — text fitted to whatever box it's given, with
// an optional blurred halo of the same glyphs behind it. Both homes of
// the widget use THIS component (the desktop copy in Background.qml and
// the Clock lock style in lock/Clock.qml), so the two can't drift apart:
// same font, same fit, same halo.
//
// Ported from NibrasShell's desktop/DesktopClock.qml — their fit trick
// is the good part: measure the string at a fixed 1000 px and scale to
// the box, instead of picking a pixel size per format. "12:30 AM -
// 06/26" and "12:30" both fill the box edge to edge with one formula,
// and switching format can never reflow or clip anything.
//
// One deliberate change to their version: they lay the glyphs out at
// 1000 px and layer EFFECT that texture (blur included), then scale the
// whole thing down — an 8000×1200 buffer re-rasterised every second for
// a :ss format. Here the 1000 px copy is metrics-only (invisible, never
// drawn) and the visible text is laid out AT the fitted size, so the
// halo's texture is box-sized: same look, a couple of orders of
// magnitude less GPU memory and per-second raster work.
//
// No ThemeManager, no config singleton: format/color/glow are plain
// properties, and the tick is its own SystemClock at second precision so
// a format with :ss runs without asking the caller for anything.
Item {
    id: root

    property string format: "hh:mm AP - MM/dd"
    property color color: Services.Colors.text
    property bool glow: true
    property real glowIntensity: 0.55   // halo blur, 0..1 (MultiEffect.blur)
    property real fill: 0.95            // share of the box the glyphs take
    property bool bold: true

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    readonly property string stamp: Qt.formatDateTime(clock.date, root.format)

    // probe: the measurement copy — invisible, metrics only, never
    // rasterised. 1000 px is arbitrary but convenient: fitting is a
    // ratio, so any fixed size gives the same answer.
    Text {
        id: probe
        visible: false
        text: root.stamp
        font.family: Services.Fonts.family
        font.pixelSize: 1000
        font.weight: root.bold ? Font.Bold : Font.Normal
        fontSizeMode: Text.FixedSize
    }

    // the size the visible copies are actually drawn at — probe size
    // scaled by how much the box wants it, i.e. their `scale` folded into
    // the font size so no oversized item ever exists
    readonly property real fit: {
        if (probe.implicitWidth <= 0 || probe.implicitHeight <= 0)
            return 0
        return Math.min(root.width / probe.implicitWidth,
                        root.height / probe.implicitHeight) * root.fill
    }
    readonly property real textSize: 1000 * root.fit

    // halo first (behind), sharp copy on top — both the same size, so
    // the blur is a 1:1 halo of the glyphs and not a stretched copy
    Text {
        id: halo
        anchors.centerIn: parent
        visible: root.glow && root.glowIntensity > 0 && root.textSize > 0
        text: root.stamp
        font.family: probe.font.family
        font.pixelSize: root.textSize
        font.weight: probe.font.weight
        fontSizeMode: Text.FixedSize
        color: root.color
        // REQUIRED by QtQuick.Effects: the effect draws a second item
        // ALONGSIDE its source rather than replacing it — with both
        // visible the sharp copy would show through the blur, so only the
        // halo carries a layer and the real text stays crisp on top.
        layer.enabled: visible
        layer.smooth: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: true
            blurEnabled: halo.visible
            blur: root.glowIntensity
            blurMax: 48
            shadowEnabled: false
        }
    }

    Text {
        anchors.centerIn: parent
        visible: root.textSize > 0
        text: root.stamp
        font.family: probe.font.family
        font.pixelSize: root.textSize
        font.weight: probe.font.weight
        fontSizeMode: Text.FixedSize
        color: root.color
        antialiasing: true
        smooth: true
    }
}
