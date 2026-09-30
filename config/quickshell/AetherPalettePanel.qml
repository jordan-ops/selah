import QtQuick
import "./services" as Services

// The controls column — aether's SettingsSidebar (Palette mode / Generate /
// Adjust) squeezed into a width an overlay can spare.
//
//   Palette    16 swatches + hex readout, and a chip when a preset owns them
//   Generate   extraction mode (23 modes in aether's own 5 groups) and the
//              Dark/Light switch — the two parameters aether exposes end-to-end
//   Presets    aether's 38 static 16-colour palettes
//   Adjust     aether's 12 sliders (saturation, vibrance, ...) plus its nudge
//              row: -H +H -S +S Cool Warm
//
// Ranges, steps and defaults come from aether's ADJUSTMENT_LIMITS and the
// mode/preset lists from its frontend constants, so nothing here is a
// re-typed copy that could drift from the app.
Item {
    id: root
    width: 300
    property string menu: ""          // "" | "modes" | "presets"
    property bool showAll: false
    property int hotSwatch: -1
    readonly property var aether: Services.Aether

    readonly property var adjustRows: ([
        { key: "vibrance",   label: "Vibrance" },
        { key: "saturation", label: "Saturation" },
        { key: "contrast",   label: "Contrast" },
        { key: "brightness", label: "Brightness" },
        { key: "shadows",    label: "Shadows" },
        { key: "highlights", label: "Highlights" },
        { key: "hueShift",   label: "Hue shift" },
        { key: "temperature",label: "Temperature" },
        { key: "tint",       label: "Tint" },
        { key: "blackPoint", label: "Black point" },
        { key: "whitePoint", label: "White point" },
        { key: "gamma",      label: "Gamma" }
    ])
    readonly property int primaryCount: 6   // aether's PRIMARY_SLIDER_COUNT

    readonly property var modeRows: {
        const out = []
        if (aether.modeGroups.length === 0) return out
        for (const g of aether.modeGroups) {
            out.push({ type: "h", label: g.label })
            for (const m of aether.modes)
                if (m.group === g.id) out.push({ type: "m", m: m })
        }
        return out
    }
    readonly property var presetRows: Object.keys(aether.presets).map(n => ({
        name: n, colors: aether.presets[n]
    }))

    function modeLabel(id) {
        for (const m of aether.modes) if (m.value === id) return m.label
        return id
    }
    function adjValue(key) {
        const l = aether.limits[key]
        const v = aether.adjustments[key]
        return v !== undefined ? Number(v) : (l ? l.default : 0)
    }
    function swatchColor(i) {
        return (aether.palette && aether.palette.length === 16) ? aether.palette[i] : "#000000"
    }

    Rectangle {
        anchors.fill: parent
        color: Services.Colors.surface
    }

    Flickable {
        id: flick
        anchors.fill: parent
        contentHeight: col.implicitHeight + 24
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: col
            x: 14
            y: 14
            width: parent.width - 28
            spacing: 10

            // ---------------- Palette ----------------
            Text {
                text: "PALETTE"
                color: Services.Colors.textMuted
                font.family: Services.Fonts.family
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1
            }

            Column {
                spacing: 3
                Row {
                    spacing: 3
                    Repeater {
                        model: 8
                        Rectangle {
                            width: 31; height: 22; radius: 3
                            color: root.swatchColor(index)
                            border.width: root.hotSwatch === index ? 2 : 1
                            border.color: root.hotSwatch === index
                                ? Services.Colors.text : Services.Colors.low
                            HoverHandler { onHoveredChanged: root.hotSwatch = hovered ? index : -1 }
                        }
                    }
                }
                Row {
                    spacing: 3
                    Repeater {
                        model: 8
                        Rectangle {
                            width: 31; height: 22; radius: 3
                            color: root.swatchColor(index + 8)
                            border.width: root.hotSwatch === index + 8 ? 2 : 1
                            border.color: root.hotSwatch === index + 8
                                ? Services.Colors.text : Services.Colors.low
                            HoverHandler { onHoveredChanged: root.hotSwatch = hovered ? index + 8 : -1 }
                        }
                    }
                }
            }

            Row {
                spacing: 6
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.hotSwatch >= 0 && aether.palette.length === 16
                        ? "#" + (root.hotSwatch + 1) + " · "
                          + aether.palette[root.hotSwatch]
                        : (aether.palette.length === 16 ? "16 colours" : "no palette yet")
                    color: Services.Colors.textMuted
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                }
                Rectangle {   // preset chip: says loudly who owns the palette
                    visible: aether.presetActive
                    height: 18; width: presetChipT.implicitWidth + 18
                    radius: 5
                    color: Services.Colors.accent
                    Text {
                        id: presetChipT
                        anchors.centerIn: parent
                        text: aether.presetName + " ✕"
                        color: Services.Colors.background
                        font.family: Services.Fonts.family
                        font.pixelSize: 11
                        font.bold: true
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: aether.clearPreset()
                    }
                }
            }

            Rectangle { width: parent.width; height: 1; color: Services.Colors.low; opacity: 0.4 }

            // ---------------- Generate ----------------
            Text {
                text: "GENERATE"
                color: Services.Colors.textMuted
                font.family: Services.Fonts.family
                font.pixelSize: 11
                font.bold: true
                font.letterSpacing: 1
            }

            Row {
                spacing: 8
                Rectangle {   // extraction mode -> grouped menu
                    width: col.width - darkLight.width - 8
                    height: 34
                    radius: 8
                    color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                   Services.Colors.text.b, 0.08)
                    border.color: Services.Colors.low
                    border.width: 1
                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.modeLabel(aether.extractMode)
                        color: Services.Colors.text
                        font.family: Services.Fonts.family
                        font.pixelSize: 12
                    }
                    Text {
                        font.family: Services.Fonts.family
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: "▾"
                        color: Services.Colors.textMuted
                        font.pixelSize: 12
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.menu = root.menu === "modes" ? "" : "modes"
                    }
                }
                Rectangle {   // Dark / Light, aether's palette-mode switch
                    id: darkLight
                    width: 104; height: 34; radius: 8
                    color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                   Services.Colors.text.b, 0.08)
                    border.color: Services.Colors.low
                    border.width: 1
                    Row {
                        anchors.fill: parent
                        Repeater {
                            model: [{ l: "Dark", v: false }, { l: "Light", v: true }]
                            delegate: Rectangle {
                                required property var modelData
                                width: 52; height: 34
                                radius: 8
                                color: aether.lightMode === modelData.v
                                    ? Services.Colors.accent : "transparent"
                                Text {
                                    anchors.centerIn: parent
                                    text: modelData.l
                                    color: aether.lightMode === modelData.v
                                        ? Services.Colors.background : Services.Colors.textMuted
                                    font.family: Services.Fonts.family
                                    font.pixelSize: 11
                                    font.bold: aether.lightMode === modelData.v
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: aether.setLightMode(modelData.v)
                                }
                            }
                        }
                    }
                }
            }

            Rectangle {
                width: col.width; height: 34; radius: 8
                color: aether.presetActive
                    ? Services.Colors.accent
                    : Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                              Services.Colors.text.b, 0.08)
                border.color: Services.Colors.low
                border.width: 1
                Text {
                    anchors.left: parent.left
                    anchors.leftMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: aether.presetActive ? "Preset · " + aether.presetName : "Presets"
                    color: aether.presetActive ? Services.Colors.background : Services.Colors.text
                    font.family: Services.Fonts.family
                    font.pixelSize: 12
                }
                Text {
                    font.family: Services.Fonts.family
                    anchors.right: parent.right
                    anchors.rightMargin: 10
                    anchors.verticalCenter: parent.verticalCenter
                    text: "▾"
                    color: aether.presetActive ? Services.Colors.background : Services.Colors.textMuted
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.menu = root.menu === "presets" ? "" : "presets"
                }
            }

            Rectangle { width: parent.width; height: 1; color: Services.Colors.low; opacity: 0.4 }

            // ---------------- Adjust ----------------
            Row {
                width: col.width
                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "ADJUST"
                    color: Services.Colors.textMuted
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 1
                }
                Item { width: parent.width - resetT.width - showT.width - 36; height: 1 }
                Text {
                    id: showT
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.showAll ? "fewer" : "all 12"
                    color: Services.Colors.accent
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.showAll = !root.showAll
                    }
                }
                Text {
                    id: resetT
                    anchors.verticalCenter: parent.verticalCenter
                    x: showT.x + showT.width + 12
                    text: "reset"
                    color: Services.Colors.textMuted
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: aether.resetAdjustments()
                    }
                }
            }

            // aether's nudge row — six one-step corrections without a slider.
            Row {
                spacing: 6
                Repeater {
                    model: [
                        { l: "-H", k: "hueDown" }, { l: "+H", k: "hueUp" },
                        { l: "-S", k: "desat" },   { l: "+S", k: "sat" },
                        { l: "Cool", k: "cool" },  { l: "Warm", k: "warm" }
                    ]
                    delegate: Rectangle {
                        required property var modelData
                        width: nudgeT.implicitWidth + 16
                        height: 24
                        radius: 6
                        color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                       Services.Colors.text.b, 0.08)
                        border.color: Services.Colors.low
                        border.width: 1
                        Text {
                            id: nudgeT
                            anchors.centerIn: parent
                            text: modelData.l
                            color: Services.Colors.textMuted
                            font.family: Services.Fonts.family
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: aether.nudge(modelData.k)
                        }
                    }
                }
            }

            Column {
                width: col.width
                spacing: 6
                Repeater {
                    model: root.adjustRows
                    delegate: AetherSlider {
                        id: sl
                        // Declaring one required property stops quickshell from
                        // injecting `index` as a context property, so both must
                        // be declared.
                        required property int index
                        required property var modelData
                        width: col.width
                        key: modelData.key
                        label: modelData.label
                        visible: root.showAll || index < root.primaryCount
                        min: aether.limits[modelData.key] ? aether.limits[modelData.key].min : -100
                        max: aether.limits[modelData.key] ? aether.limits[modelData.key].max : 100
                        step: aether.limits[modelData.key] ? aether.limits[modelData.key].step : 5
                        def: aether.limits[modelData.key] ? aether.limits[modelData.key].default : 0
                        value: root.adjValue(modelData.key)
                        onCommitted: v => aether.setAdjust(modelData.key, v)
                    }
                }
            }
        }
    }

    // ---------------- overlays ----------------
    MouseArea {   // click away closes whichever menu is open
        anchors.fill: parent
        visible: root.menu !== ""
        onClicked: root.menu = ""
    }

    Rectangle {
        visible: root.menu === "modes"
        anchors.fill: parent
        radius: 10
        color: Services.Colors.background
        border.color: Services.Colors.accent
        border.width: 1

        ListView {
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            model: root.modeRows
            spacing: 2
            delegate: Item {
                required property int index
                readonly property var r: root.modeRows[index]
                readonly property bool isHeader: r.type === "h"
                // Everything that touches r.m goes through these: bindings are
                // evaluated even while the row is hidden, and header rows have
                // no r.m at all (nor mode rows a r.label).
                readonly property string headerLabel: r.label ? r.label : ""
                readonly property string modeLabel: r.m ? r.m.label : ""
                readonly property string modeDesc: r.m ? r.m.description : ""
                readonly property bool picked: !!r.m
                        && aether.extractMode === r.m.value

                width: ListView.view.width
                height: isHeader ? 24 : 44

                Text {
                    visible: parent.isHeader
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: parent.headerLabel
                    color: Services.Colors.accent
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    font.bold: true
                    font.letterSpacing: 1
                }

                Rectangle {
                    visible: !parent.isHeader
                    anchors.fill: parent
                    radius: 6
                    color: parent.picked ? Services.Colors.accent
                        : Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                  Services.Colors.text.b, 0.06)

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.top: parent.top
                        anchors.topMargin: 5
                        text: parent.parent.modeLabel
                        color: parent.parent.picked ? Services.Colors.background
                                                    : Services.Colors.text
                        font.family: Services.Fonts.family
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }
                    Text {
                        font.family: Services.Fonts.family
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 5
                        text: parent.parent.modeDesc
                        color: parent.parent.picked ? Services.Colors.background
                                                    : Services.Colors.textMuted
                        font.pixelSize: 10
                        elide: Text.ElideRight
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (parent.parent.r.m)
                                aether.setExtractMode(parent.parent.r.m.value)
                            root.menu = ""
                        }
                    }
                }
            }
        }
    }

    Rectangle {
        visible: root.menu === "presets"
        anchors.fill: parent
        radius: 10
        color: Services.Colors.background
        border.color: Services.Colors.accent
        border.width: 1

        ListView {
            anchors.fill: parent
            anchors.margins: 6
            clip: true
            model: root.presetRows
            spacing: 2
            delegate: Rectangle {
                id: prow
                required property int index
                width: ListView.view.width
                height: 34
                radius: 6
                color: aether.presetActive && aether.presetName === prow.r.name
                    ? Services.Colors.accent
                    : Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                              Services.Colors.text.b, 0.06)
                readonly property var r: root.presetRows[prow.index]
                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 1
                    // prow.index, not index: this Repeater's own index (0-15)
                    // shadows the outer one inside its delegates.
                    Repeater {
                        model: 16
                        Rectangle {
                            width: 6; height: 22; radius: 1
                            color: prow.r.colors[modelData]
                        }
                    }
                }
                Text {
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    text: prow.r.name
                    color: aether.presetActive && aether.presetName === prow.r.name
                        ? Services.Colors.background : Services.Colors.text
                    font.family: Services.Fonts.family
                    font.pixelSize: 12
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        aether.applyPreset(prow.r.name)
                        root.menu = ""
                    }
                }
            }
        }
    }
}
