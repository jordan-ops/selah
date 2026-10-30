pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // raw parsed JSON — kept as "data" to avoid clashing with the
    // "palette" key that already exists inside the JSON itself
    property var data: ({})
    readonly property var md3: data.md3 || ({})

    // fallback values match your current hardcoded colors, so nothing
    // breaks before the file exists yet or a key is missing
    readonly property color background:  md3.background            || "#282828"
    readonly property color surface:     md3.surface_variant       || "#1f1f1f"
    readonly property color surfaceAlt:  md3.secondary_container   || "#3a3a3a"
    readonly property color accent:      md3.primary               || "#1db954"
    readonly property color text:        md3.on_background         || "#ffffff"
    readonly property color critical:    md3.error                 || "#e74c3c"
    readonly property color low:         md3.outline                || "#555555"

    // on_surface_variant is tuned for M3's surface_variant chip, not this
    // shell's near-black `background` — matte-black ships #333333 on
    // #121212, which turned every muted label invisible (cheatsheet
    // comments, settings sidebar, row descriptions). Floor muted text at
    // ~3:1 against the background: lift dark-on-dark toward white,
    // darken light-on-light toward black, keep the theme's hue otherwise.
    readonly property color textMuted: root.ensureContrast(
        md3.on_surface_variant || "#aaaaaa", 3.0)

    // SOLID ACCENT SURFACES THAT CARRY TEXT — the launcher's selection
    // pill, the delete-confirm buttons, text-selection highlights. A
    // theme is free to derive primary == on_background — kanagawa
    // ships #dcd7ba for BOTH — which paints the label in exactly the
    // highlight's color and the text vanishes. This is the accent with
    // its hue kept, shifted toward black or white (whichever reaches
    // the floor in the fewer steps) until `text` sits on it at >= 4.5:1
    // — WCAG AA for the normal-size launcher names. Themes where the
    // label already clears the floor get the raw accent back,
    // byte-identical. Decorative accents (dots, rails, OSD fills) that
    // carry NO text keep plain `accent`.
    readonly property color accentSurface: root.contrastAgainst(
        accent, text, 4.5)

    // c shifted toward white or black until it clears `min` against
    // `bg` (WCAG relative-luminance ratio). Both directions are tried
    // and the smaller step wins: on a near-black bg only lightening
    // can reach the floor (darkening caps at bg/0.05), so choosing by
    // fg-vs-bg side would pick the dead end.
    function contrastAgainst(c: color, bg: color, min: real): color {
        const relLum = (x) => {
            const lin = (v) => v <= 0.04045 ? v / 12.92
                                             : Math.pow((v + 0.055) / 1.055, 2.4)
            return 0.2126 * lin(x.r) + 0.7152 * lin(x.g) + 0.0722 * lin(x.b)
        }
        const ratio = (a, b) => {
            const la = relLum(a), lb = relLum(b)
            return (Math.max(la, lb) + 0.05) / (Math.min(la, lb) + 0.05)
        }
        if (ratio(c, bg) >= min)
            return c
        const seek = (target) => {
            for (let t = 0.05; t <= 1.0001; t += 0.05) {
                const mixed = Qt.rgba(c.r + (target.r - c.r) * t,
                                      c.g + (target.g - c.g) * t,
                                      c.b + (target.b - c.b) * t, c.a)
                if (ratio(mixed, bg) >= min)
                    return { t: t, color: mixed }
            }
            return null
        }
        const up = seek(Qt.rgba(1, 1, 1, c.a))
        const down = seek(Qt.rgba(0, 0, 0, c.a))
        if (up && down)
            return up.t <= down.t ? up.color : down.color
        if (up) return up.color
        if (down) return down.color
        return c   // unreachable floor (background sits at ~0 contrast)
    }

    // historical name — textMuted floors against the shell background;
    // same machinery as contrastAgainst with `bg` pinned to it
    function ensureContrast(c: color, min: real): color {
        return contrastAgainst(c, root.background, min)
    }

    // alias — several components call Services.Colors.text_muted
    // (snake_case) while the property above is textMuted; without
    // this those bindings resolve to undefined and render transparent.
    readonly property color text_muted:  textMuted

    // Panel fill for surfaces that should let the wallpaper through —
    // the bar pill, control center, settings window and aether picker.
    // Same RGB as `background`, alpha from the "appearance.transparency"
    // choice (0/15/30/45 percent clear; 0 = pixel-identical to plain
    // background). TEXT and glyph roles must keep the opaque
    // `background` — a half-transparent label reads as broken type.
    readonly property color panel: {
        const raw = Settings.values["appearance.transparency"]
        const n = parseInt(raw === undefined || raw === null ? "0" : String(raw), 10)
        const t = isNaN(n) ? 0 : Math.max(0, Math.min(100, n))
        return Qt.rgba(background.r, background.g, background.b, 1 - t / 100)
    }

    FileView {
        id: colorFile
        path: Quickshell.env("HOME") + "/.local/state/quickshell/generated/colors.json"
        watchChanges: true          // re-fires onFileChanged when matugen rewrites the file
        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(text())
            } catch (e) {
                console.log("Colors.qml: failed to parse colors.json —", e)
            }
        }
    }
}
