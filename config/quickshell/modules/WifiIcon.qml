import QtQuick
import "../services" as Services

// Network state as a Nerd Font glyph — no custom Shape drawing, the
// font already carries the whole family (md-wifi / md-ethernet /
// md-wifi-off all live in GoogleSansCode Nerd Font). Icon only: the
// SSID / "Wired" / "Offline" text is gone, but the three network
// states stay readable without words:
//
//   wifi connected  → md-wifi (󰤨), full-colour glyph
//   wired connected → md-ethernet (󰈀) in the muted colour (online,
//                     just not over wifi)
//   offline         → md-wifi-off (󰤭), dimmed to 0.55 — same opacity
//                     the old centre glyph used
//
// The glyphs come from the same three-way mapping as
// Services.Network.glyph, but derived from THIS item's connected/wifi
// properties so a caller can pin a state (same contract as
// BatteryIcon's level/charging).
//
// It owns no click: the status chip around it (wide row) or the compact
// capsule's own area (see compactStatus in Bar.qml) handles that, so the
// glyph never eats a click meant for the pill.
Item {
    id: root
    width: 16
    height: 12

    // bound to the service — plain (not readonly) so a caller can pin a
    // state, same contract as BatteryIcon's level/charging
    property bool connected: Services.Network.connected
    property bool wifi: Services.Network.isWifi
    property color glyphColor: wifi ? Services.Colors.text
                                    : Services.Colors.textMuted

    // three states, same strings Services.Network.glyph serves
    readonly property string glyph: !root.connected ? "\u{f092d}"   // md-wifi-off
        : root.wifi ? "\u{f0928}"                                   // md-wifi
        : "\u{f0200}"                                               // md-ethernet

    // offline dims the way the old centre glyph did
    opacity: connected ? 1 : 0.55

    Behavior on glyphColor {
        ColorAnimation {
            duration: Services.Motion.effects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Services.Motion.standardCurve
        }
    }
    Behavior on opacity {
        NumberAnimation {
            duration: Services.Motion.effects
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Services.Motion.standardCurve
        }
    }

    Text {
        anchors.centerIn: parent
        font.family: Services.Fonts.family
        font.pixelSize: 14
        text: root.glyph
        color: root.glyphColor

        Behavior on color {
            ColorAnimation {
                duration: Services.Motion.effects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.standardCurve
            }
        }
    }
}
