pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// The typed design-token layer — the ONE reader of colors.json.
//
// Owns the FileView on the generated palette (switch-theme.sh writes it
// in place so inotify survives) and answers the eight semantic roles the
// shell paints with, under the QML-semantic camelCase names of the `qtc`
// block that toml2colors.py emits. Themes predating [qtc] behave
// identically: the converter mirrors every md3 derivation into qtc, and
// each token still falls back md3-first below, so an md3-only file from
// before this layer existed yields byte-identical colours.
//
// RAW tokens only. The derived roles — the 3:1 floor on muted text, the
// WCAG-checked accentSurface, the transparency-aware panel — live in
// services/Colors.qml, which delegates its raw tokens here and keeps the
// whole Services.Colors.* API intact (hundreds of bindings untouched).
Singleton {
    id: root

    // raw parsed JSON. `qtc` = the typed block; `md3` kept as the
    // fallback source and for consumers that read the historical keys
    // (widgets/Colors.qml reads md3.surface_variant off Colors.md3)
    property var data: ({})
    readonly property var md3: data.md3 || ({})
    readonly property var qtc: data.qtc || ({})

    // ── the eight roles ────────────────────────────────────────────────
    // qtc first (explicit [qtc] override, else the converter's md3
    // mirror), then md3 (an md3-only file), then the same hardcoded
    // defaults services/Colors.qml has always shipped — a missing or
    // partial file never renders transparent.
    readonly property color background: qtc.background  || md3.background           || "#282828"
    readonly property color surface:     qtc.surface     || md3.surface_variant      || "#1f1f1f"
    readonly property color surfaceAlt:  qtc.surfaceAlt  || md3.secondary_container  || "#3a3a3a"
    readonly property color accent:      qtc.accent      || md3.primary              || "#1db954"
    readonly property color text:        qtc.text        || md3.on_background        || "#ffffff"
    readonly property color critical:    qtc.critical    || md3.error                || "#e74c3c"
    readonly property color low:         qtc.low         || md3.outline              || "#555555"

    // RAW muted text — no contrast floor here. Colors.textMuted floors it
    // at 3:1 against the background before anything paints with it (the
    // on_surface_variant key is tuned for M3's chip, not our near-black
    // background — see the note there).
    readonly property color textMuted: qtc.textMuted || md3.on_surface_variant || "#aaaaaa"

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/quickshell/generated/colors.json"
        watchChanges: true          // re-fires onFileChanged when switch-theme.sh rewrites it
        onFileChanged: reload()
        onLoaded: {
            try {
                root.data = JSON.parse(text())
            } catch (e) {
                console.log("Palette.qml: failed to parse colors.json —", e)
            }
        }
    }
}
