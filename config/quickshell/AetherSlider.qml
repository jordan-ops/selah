import QtQuick
import "./services" as Services

// One colour-edit row for AetherPalettePanel — aether's AdjustmentSlider in
// this setup's visual language (same track/handle geometry as
// SettingsSliderRow.qml, but driven by Aether's 12-parameter table).
//
// Range, step and default all come from aether's own ADJUSTMENT_LIMITS, so
// dragging a slider here and dragging one in the aether app land on the same
// number. Changes are emitted live; Aether.qml debounces the re-extraction.
Item {
    id: root

    property string key: ""
    property string label: ""
    property real value: 0
    property real min: -100
    property real max: 100
    property real step: 5
    // aether's default for this slider (0 for most, 1.0 for gamma) — drives
    // both the "is this edited?" styling and where the fill starts.
    property real def: 0
    property bool atDefault: Math.abs(value - def) < 0.0001

    signal committed(real v)

    width: parent ? parent.width : 260
    height: 28

    function clamp(v) { return Math.max(min, Math.min(max, v)) }
    function snap(v) { return clamp(Math.round(v / step) * step) }

    // Trailing zeros trimmed so -15.0 reads "-15" and 1.0 reads "1".
    function fmt(v) {
        const s = (Math.round(v * 10) / 10).toString()
        return s
    }

    Row {
        anchors.fill: parent
        spacing: 8

        Text {
            id: labelT
            width: 86
            anchors.verticalCenter: parent.verticalCenter
            text: root.label
            color: root.atDefault ? Services.Colors.textMuted : Services.Colors.text
            font.family: Services.Fonts.family
            font.pixelSize: 12
        }

        Item {
            id: trackBox
            width: parent.width - labelT.width - valueT.width
                   - parent.spacing * 2
            height: parent.height

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 5
                radius: 3
                color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                               Services.Colors.text.b, 0.16)

                // Fill runs from aether's default for this slider to the
                // handle, so a slider sitting on its default shows no fill at
                // all — and gamma (default 1.0, range 0.5–2.0) starts mid-track.
                readonly property real zeroX: track.width
                    * (root.def - root.min) / Math.max(0.0001, root.max - root.min)

                Rectangle {
                    // track.zeroX, not zeroX: unqualified names only see own
                    // properties, ids and the component root — not an
                    // enclosing object's properties.
                    x: Math.min(handle.x + handle.width / 2, track.zeroX)
                    width: Math.abs(handle.x + handle.width / 2 - track.zeroX)
                    height: parent.height
                    radius: 3
                    color: Services.Colors.accent
                }

                Rectangle {
                    id: handle
                    x: (track.width - width) * (root.value - root.min)
                       / Math.max(0.0001, root.max - root.min)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 13
                    height: 13
                    radius: 7
                    color: Services.Colors.accent
                    border.color: Services.Colors.background
                    border.width: 2
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8              // generous grab zone
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => setFrom(mouse.x)
                    onPositionChanged: mouse => { if (pressed) setFrom(mouse.x) }
                    function setFrom(x) {
                        const norm = Math.max(0, Math.min(1, x / track.width))
                        root.committed(root.snap(root.min + norm * (root.max - root.min)))
                    }
                }
            }
        }

        Text {
            id: valueT
            width: 42
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: root.fmt(root.value)
            color: root.atDefault ? Services.Colors.textMuted : Services.Colors.accent
            font.family: Services.Fonts.family
            font.pixelSize: 12
            font.bold: !root.atDefault
        }
    }
}
