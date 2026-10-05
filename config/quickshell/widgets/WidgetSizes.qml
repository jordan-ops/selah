pragma Singleton

import Quickshell
import QtQuick

// Ported from Nebula's modules/utils/WidgetSizes.qml (GPL-3.0) — the grid
// lattice every widget snaps to: 90px cells with a 20px gutter, a centred
// origin derived from the live widget screen, and the card surface tokens.
// Verbatim; only the module import is gone (SettingsConfig/Colors/GlobalStates
// are siblings here).
Singleton {
    id: root

    readonly property int cell: 90
    readonly property int gutter: 20
    readonly property int pitch: cell + gutter

    function span(n) { return n * pitch - gutter }
    function cellsFor(px) { return Math.max(1, Math.round((px + gutter) / pitch)) }
    function cellsCovering(px) { return Math.max(1, Math.ceil((px + gutter) / pitch - 0.001)) }

    readonly property int rowStep: pitch / 2
    function rowsFor(px) { return Math.max(0.5, Math.round((px + gutter) / rowStep) / 2) }
    function halvesCovering(px) { return Math.max(1, Math.ceil((px + gutter) / rowStep - 0.001)) }

    readonly property vector2d screenSize: GlobalStates.widgetScreenSize
    readonly property int gridCols: Math.max(1, Math.floor((screenSize.x - gutter) / pitch))
    readonly property int gridRows: Math.max(1, Math.floor((screenSize.y - gutter) / pitch))
    readonly property int originX: Math.round((screenSize.x - span(gridCols)) / 2)
    readonly property int originY: Math.round((screenSize.y - span(gridRows)) / 2)

    readonly property int colStep: pitch / 2
    function colAt(x) { return Math.round((x - originX) / pitch) }
    function rowAt(y) { return Math.round((y - originY) / rowStep) / 2 }

    function snapX(x, w) {
        const c = Math.max(0, Math.min(Math.round((x - originX) / colStep), gridCols * 2 - halvesCovering(w)))
        return originX + c * colStep
    }
    function snapY(y, h) {
        const r = Math.max(0, Math.min(Math.round((y - originY) / rowStep),
                                       gridRows * 2 - halvesCovering(h)))
        return originY + r * rowStep
    }

    readonly property int radius: 24
    function padFor(w) { return w <= span(2) + 1 ? 16 : 20 }
    function nestedRadius(w) { return Math.max(6, radius - padFor(w)) }

    readonly property string cardStyle: {
        const s = SettingsConfig.widgets.cardStyle
            ?? ((SettingsConfig.widgets.blurBackground ?? false) ? "frosted" : "flat")
        return s === "liquid" ? "frosted" : s
    }

    readonly property bool blurBackground: root.cardStyle !== "flat"
    readonly property real cardOpacity: SettingsConfig.widgets.cardOpacity ?? 0.60

    readonly property color cardColor: root.cardStyle === "frosted"
        ? Qt.alpha(Colors.surface, root.cardOpacity)
        : Colors.surface

    // ── Named tiles ───────────────────────────────────────────────────
    readonly property size small: Qt.size(span(2), span(2))
    readonly property size wide:  Qt.size(span(3), span(2))
    readonly property size strip: Qt.size(span(3), span(1.5))
    readonly property size tall:  Qt.size(span(2), span(3))
    readonly property size large: Qt.size(span(3), span(3))
}
