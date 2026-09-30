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
    readonly property color textMuted:   md3.on_surface_variant    || "#aaaaaa"
    readonly property color critical:    md3.error                 || "#e74c3c"
    readonly property color low:         md3.outline                || "#555555"

    // alias — several components call Services.Colors.text_muted
    // (snake_case) while the property above is textMuted; without
    // this those bindings resolve to undefined and render transparent.
    readonly property color text_muted:  textMuted

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
