pragma Singleton
import Quickshell
import QtQuick
import "../services" as Services

// Palette bridge for the ported Nebula widgets (Nebula shell, GPL-3.0).
//
// The ported files speak Nebula's Material-3 role names — Colors.primary,
// Colors.surfaceContainerHigh, Colors.tertiary… (~1,700 bindings). Instead of
// rewriting every one, this singleton ANSWERS those names from our own live
// palette (services/Colors.qml, which already tracks every theme switch):
// the eight md3 roles our generated colors.json carries map straight across,
// and the rest are derived here so widgets still get a full tonal range —
// elevation steps blend the background toward the text colour, secondary and
// tertiary hue-rotate the accent, and every *Text/on-role is picked by WCAG
// contrast against the role it sits on.
Singleton {
    id: root

    // ── colour maths ──────────────────────────────────────────────────
    function _hex(r, g, b) {
        const h = v => Math.max(0, Math.min(255, Math.round(v))).toString(16).padStart(2, "0")
        return "#" + h(r) + h(g) + h(b)
    }

    // Accepts "#rgb", "#rrggbb", "#aarrggbb" or a QML colour — returns
    // [r, g, b] (0-255) or the input untouched when it can't parse.
    function _rgb(c) {
        const s = String(c)
        if (s.length < 4 || s[0] !== "#") return null
        let x = s.slice(1)
        if (x.length === 3) x = x[0] + x[0] + x[1] + x[1] + x[2] + x[2]
        if (x.length !== 6 && x.length !== 8) return null
        const n = parseInt(x, 16)
        if (isNaN(n)) return null
        if (x.length === 8) return [(n >>> 16) & 255, (n >>> 8) & 255, n & 255]
        return [(n >>> 16) & 255, (n >>> 8) & 255, n & 255]
    }

    // blend two colours: t = 0 → a, t = 1 → b
    function mix(a, b, t) {
        const ra = _rgb(a), rb = _rgb(b)
        if (!ra || !rb) return a
        return _hex(ra[0] + (rb[0] - ra[0]) * t,
                    ra[1] + (rb[1] - ra[1]) * t,
                    ra[2] + (rb[2] - ra[2]) * t)
    }

    // rotate hue by degrees, keeping saturation/lightness
    function hueShift(c, deg) {
        const r = _rgb(c)
        if (!r) return c
        const rr = r[0] / 255, gg = r[1] / 255, bb = r[2] / 255
        const mx = Math.max(rr, gg, bb), mn = Math.min(rr, gg, bb)
        let h = 0
        const l = (mx + mn) / 2
        const d = mx - mn
        let s = 0
        if (d > 0.0001) {
            s = l > 0.5 ? d / (2 - mx - mn) : d / (mx + mn)
            if (mx === rr) h = ((gg - bb) / d + (gg < bb ? 6 : 0))
            else if (mx === gg) h = (bb - rr) / d + 2
            else h = (rr - gg) / d + 4
            h /= 6
        }
        h = (h + deg / 360 + 1) % 1
        // hsl → rgb
        const hue2 = (p, q, t) => {
            if (t < 0) t += 1
            if (t > 1) t -= 1
            if (t < 1 / 6) return p + (q - p) * 6 * t
            if (t < 1 / 2) return q
            if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
            return p
        }
        const q = l < 0.5 ? l * (1 + s) : l + s - l * s
        const p = 2 * l - q
        return _hex(hue2(p, q, h + 1 / 3) * 255, hue2(p, q, h) * 255, hue2(p, q, h - 1 / 3) * 255)
    }

    // WCAG-ish contrast: black or white, whichever reads better on bg
    function on(bg) {
        const r = _rgb(bg)
        if (!r) return "#ffffff"
        const lin = v => {
            v /= 255
            return v <= 0.03928 ? v / 12.92 : Math.pow((v + 0.055) / 1.055, 2.4)
        }
        const lum = 0.2126 * lin(r[0]) + 0.7152 * lin(r[1]) + 0.0722 * lin(r[2])
        const cBlack = (lum + 0.05) / 0.05
        const cWhite = 1.05 / (lum + 0.05)
        return cBlack >= cWhite ? "#000000" : "#ffffff"
    }

    // ── our live palette ──────────────────────────────────────────────
    readonly property color _bg:       Services.Colors.background
    readonly property color _text:     Services.Colors.text
    readonly property color _accent:   Services.Colors.accent
    readonly property color _err:      Services.Colors.critical
    readonly property color _outline:  Services.Colors.low
    readonly property color _variant:  Services.Colors.md3.surface_variant     || Services.Colors.surface
    readonly property color _variantOn: Services.Colors.md3.on_surface_variant || Services.Colors.textMuted
    readonly property color _sel:      Services.Colors.md3.secondary_container || Services.Colors.surfaceAlt

    // ── M3 roles ──────────────────────────────────────────────────────
    readonly property string primary:   String(_accent)
    readonly property string primaryText: on(String(_accent))

    readonly property string surface:  mix(String(_bg), "#ffffff", 0.05)
    readonly property string surfaceText: String(_text)
    readonly property string surfaceVariant: String(_variant)
    readonly property string surfaceVariantText: String(_variantOn)

    // elevation: the standard M3 container ramp, approximated by stepping
    // the background toward the foreground colour
    readonly property string surfaceContainerLowest: mix(String(_bg), "#000000", 0.10)
    readonly property string surfaceContainerLow:     mix(String(_bg), "#ffffff", 0.03)
    readonly property string surfaceContainer:        mix(String(_bg), "#ffffff", 0.06)
    readonly property string surfaceContainerHigh:    mix(String(_bg), "#ffffff", 0.10)
    readonly property string surfaceContainerHighest: mix(String(_bg), "#ffffff", 0.15)
    readonly property string surfaceDim:    mix(String(_bg), "#000000", 0.15)
    readonly property string surfaceBright: mix(String(_bg), "#ffffff", 0.12)

    readonly property string outline:        String(_outline)
    readonly property string outlineVariant: mix(String(_outline), String(_bg), 0.55)

    readonly property string secondary:          hueShift(String(_accent), 30)
    readonly property string secondaryText:      on(hueShift(String(_accent), 30))
    readonly property string secondaryContainer: mix(hueShift(String(_accent), 30), String(_bg), 0.72)
    readonly property string secondaryContainerText: on(mix(hueShift(String(_accent), 30), String(_bg), 0.72))

    readonly property string tertiary:          hueShift(String(_accent), -35)
    readonly property string tertiaryText:      on(hueShift(String(_accent), -35))
    readonly property string tertiaryContainer: mix(hueShift(String(_accent), -35), String(_bg), 0.72)
    readonly property string tertiaryContainerText: on(mix(hueShift(String(_accent), -35), String(_bg), 0.72))

    readonly property string primaryContainer: mix(String(_accent), String(_bg), 0.74)
    readonly property string primaryContainerText: on(mix(String(_accent), String(_bg), 0.74))

    readonly property string error:          String(_err)
    readonly property string errorText:      on(String(_err))
    readonly property string errorContainer: mix(String(_err), String(_bg), 0.76)
    readonly property string errorContainerText: on(mix(String(_err), String(_bg), 0.76))

    readonly property string shadow: "#000000"
    readonly property string scrim:  "#000000"

    readonly property string inverseSurface:     mix(String(_text), String(_bg), 0.88)
    readonly property string inverseSurfaceText:  on(mix(String(_text), String(_bg), 0.88))
    readonly property string inversePrimary:      mix(String(_accent), String(_text), 0.4)

    // Belt and braces for kit files that read roles we don't model above.
    readonly property string primaryInverse: inverseSurface
    readonly property string background: String(_bg)
}
