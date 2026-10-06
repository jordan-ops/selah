// Ported from Nebula's Widgets/WidgetQuickAdd.qml (GPL-3.0) — qs.modules imports
// dropped: SettingsConfig, GlobalStates, Colors, M3Motion, PreviewData,
// WallpaperTheme, WidgetCatalog/Host/DesignStage and the kit are all
// siblings in widgets/ now.
//
// Reshaped to this shell's bar concept — one container that morphs between
// two UIs instead of a card popping into being: it is born as the highlighted
// "+" cell (accent tint + add glyph), springs open with the bar's spatial
// spring into the picker, and cross-fades its body in place at centerIn the
// way the pill swaps mode content. Close reverses the same morph back down
// to the cell before fading. Surface + hairline low border are the pill's
// card roles straight from services/Colors.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../services" as Services

Item {
    id: root
    anchors.fill: parent

    readonly property int col: GlobalStates.widgetQuickAdd.x
    readonly property int halfRow: GlobalStates.widgetQuickAdd.y
    readonly property bool open: GlobalStates.widgetEditMode && root.col >= 0

    // born = cell-sized square, grown = sprung-open picker. One container,
    // two UIs; the binding flips grown at birth so the spring plays from the
    // cell, and reverse-falls back to the cell on close.
    property bool grown: false
    property bool held: false

    visible: root.open || root.held
    enabled: root.open

    property string filter: ""

    onOpenChanged: {
        if (root.open) {
            root.held = false
            hideTimer.stop()
            root.grown = false
            // One frame at cell size, then spring open. Focus lands the same
            // tick — the bar keeps its mode content live from frame 1 too.
            Qt.callLater(() => {
                root.grown = true
                quickInput.forceActiveFocus()
            })
        } else {
            root.grown = false
            root.filter = ""
            quickInput.text = ""
            quickInput.focus = false
            root.held = true
            hideTimer.restart()
        }
    }

    Timer {
        id: hideTimer
        interval: 320
        onTriggered: root.held = false
    }

    readonly property real sc: GlobalStates.widgetStageScale
    readonly property point org: GlobalStates.widgetStageOrigin
    readonly property real cellX: root.org.x + (WidgetSizes.originX + root.col * WidgetSizes.pitch) * root.sc
    readonly property real cellY: root.org.y + (WidgetSizes.originY + root.halfRow * WidgetSizes.rowStep) * root.sc
    readonly property real cellSide: WidgetSizes.cell * root.sc
    readonly property rect canvasRect: Qt.rect(root.org.x, root.org.y,
                                               GlobalStates.widgetScreenSize.x * root.sc,
                                               GlobalStates.widgetScreenSize.y * root.sc)

    // The grown picker sits ON its cell (it morphed out of it), clamped so
    // the edges of the canvas can't cut it off.
    readonly property real popW: 312
    readonly property real popH: body.implicitHeight + 28
    readonly property real targetX: Math.max(root.canvasRect.x + 8,
        Math.min(root.canvasRect.x + root.canvasRect.width - root.popW - 8, root.cellX))
    readonly property real targetY: Math.max(root.canvasRect.y + 8,
        Math.min(root.canvasRect.y + root.canvasRect.height - root.popH - 8, root.cellY))

    readonly property var candidates: {
        const needle = root.filter.trim().toLowerCase()
        const out = []
        const cat = WidgetCatalog.catalog
        for (let s = 0; s < cat.length; s++) {
            const sec = cat[s]
            for (let i = 0; i < sec.items.length; i++) {
                const it = sec.items[i]
                if (WidgetCatalog.familyOn(it))
                    continue
                if (needle !== "" && it.label.toLowerCase().indexOf(needle) < 0
                    && sec.section.toLowerCase().indexOf(needle) < 0)
                    continue
                out.push({ entry: it, section: sec.section, glyph: sec.icon ?? "widgets" })
                if (out.length >= 5)
                    return out
            }
        }
        return out
    }

    function drop(entry) {
        const size = WidgetCatalog.tileSize(entry)
        const c = root.col
        const r = root.halfRow
        GlobalStates.widgetQuickAdd = Qt.point(-1, -1)
        WidgetCatalog.placeAt(entry, c, r, size.width, size.height)
    }

    function close() {
        GlobalStates.widgetQuickAdd = Qt.point(-1, -1)
    }

    MouseArea {
        anchors.fill: parent
        z: -1
        onClicked: root.close()
    }

    Rectangle {
        id: card
        x: root.open && root.grown ? root.targetX : root.cellX
        y: root.open && root.grown ? root.targetY : root.cellY
        width: root.open && root.grown ? root.popW : root.cellSide
        height: root.open && root.grown ? root.popH : root.cellSide
        radius: 16
        // The bar always clips: content lives inside a container that changes
        // size under it, and mid-spring the body would poke past the edges.
        clip: true

        Behavior on x { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
        Behavior on y { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
        Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
        Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

        color: root.grown ? Services.Colors.surface : Qt.alpha(Services.Colors.accent, 0.16)
        border.width: 1
        border.color: root.grown ? Services.Colors.low : Services.Colors.accent
        opacity: root.open ? 1 : 0
        Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast } }
        Behavior on border.color { ColorAnimation { duration: Services.Motion.effectsFast } }
        Behavior on opacity {
            NumberAnimation {
                duration: Services.Motion.effectsFast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.emphasizedDecelerate
            }
        }

        // The born state: the "+" cell the picker grows out of.
        MaterialIconSymbol {
            anchors.centerIn: parent
            content: "add"
            iconSize: Math.max(12, 20 * root.sc)
            customColor: Services.Colors.accent
            opacity: root.grown ? 0 : 1
            visible: opacity > 0.01
            Behavior on opacity {
                NumberAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }
        }

        // Fixed-size body, centered: the container springs behind it while it
        // cross-fades, so nothing re-layouts or stretches mid-morph (the
        // pill's mode content works the same way). Always instantiated so
        // popH has a live implicit height even before the first frame.
        ColumnLayout {
            id: body
            width: root.popW - 28
            height: implicitHeight
            anchors.centerIn: parent
            spacing: 10
            opacity: root.grown ? 1 : 0
            enabled: root.grown
            Behavior on opacity {
                NumberAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 2
                spacing: 6

                CustomText {
                    Layout.fillWidth: true
                    content: "ADD HERE · COL " + (root.col + 1) + ", ROW " + (Math.floor(root.halfRow / 2) + 1)
                    size: 10
                    weight: 700
                    customColor: Services.Colors.accent
                    font.letterSpacing: 1.3
                }

                MaterialIconSymbol {
                    content: "close"
                    iconSize: 15
                    customColor: Services.Colors.textMuted

                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.close()
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 36
                radius: 18
                color: Services.Colors.surfaceAlt
                border.width: 1
                border.color: quickInput.activeFocus ? Qt.alpha(Services.Colors.accent, 0.7) : "transparent"
                Behavior on border.color { ColorAnimation { duration: Services.Motion.effectsFast } }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 8

                    MaterialIconSymbol {
                        content: "search"
                        iconSize: 15
                        customColor: Services.Colors.textMuted
                    }

                    TextInput {
                        id: quickInput
                        Layout.fillWidth: true
                        clip: true
                        text: root.filter
                        font.family: SettingsConfig.general.defaultFont ?? "Rubik"
                        font.pixelSize: 12
                        font.weight: 500
                        color: Services.Colors.text
                        selectionColor: Qt.alpha(Services.Colors.accent, 0.4)
                        selectedTextColor: Services.Colors.text
                        verticalAlignment: TextInput.AlignVCenter
                        onTextChanged: root.filter = quickInput.text
                        onActiveFocusChanged: GlobalStates.widgetTextFocus = quickInput.activeFocus
                        Keys.onEscapePressed: root.close()
                        Keys.onReturnPressed: {
                            if (root.candidates.length > 0)
                                root.drop(root.candidates[0].entry)
                        }

                        CustomText {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: quickInput.text === ""
                            content: "Type to filter"
                            size: 12
                            customColor: Services.Colors.textMuted
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                    model: root.candidates

                    delegate: Rectangle {
                        id: hit
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        implicitHeight: 48
                        radius: 10
                        color: hit.index === 0 ? Qt.alpha(Services.Colors.accent, 0.14)
                            : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 9
                            anchors.rightMargin: 12
                            spacing: 10

                            Rectangle {
                                Layout.preferredWidth: 32
                                Layout.preferredHeight: 32
                                radius: 10
                                color: hit.index === 0 ? Qt.alpha(Services.Colors.accent, 0.18)
                                    : Services.Colors.surfaceAlt

                                MaterialIconSymbol {
                                    anchors.centerIn: parent
                                    content: hit.modelData.glyph
                                    iconSize: 16
                                    customColor: hit.index === 0 ? Services.Colors.accent : Services.Colors.textMuted
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                CustomText {
                                    Layout.fillWidth: true
                                    content: hit.modelData.entry.label
                                    size: 13
                                    weight: 600
                                    customColor: Services.Colors.text
                                }

                                CustomText {
                                    Layout.fillWidth: true
                                    content: hit.modelData.section
                                    size: 11
                                    customColor: Services.Colors.textMuted
                                }
                            }

                            MaterialIconSymbol {
                                content: hit.index === 0 ? "keyboard_return" : "add"
                                iconSize: 15
                                customColor: hit.index === 0 ? Services.Colors.accent : Services.Colors.textMuted
                            }
                        }

                        RippleEffect {
                            id: hitRipple
                            anchors.fill: parent
                            radius: 10
                            hoverColor: Qt.alpha(Services.Colors.accent, 0.07)
                            rippleColor: Qt.alpha(Services.Colors.accent, 0.16)
                            onClicked: root.drop(hit.modelData.entry)
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                    implicitHeight: 44
                    visible: root.candidates.length === 0

                    CustomText {
                        anchors.centerIn: parent
                        content: "Nothing left to add here"
                        size: 12
                        customColor: Services.Colors.textMuted
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 2
                spacing: 8

                CustomText {
                    Layout.fillWidth: true
                    content: "Esc closes"
                    size: 11
                    customColor: Services.Colors.textMuted
                }

                CustomText {
                    content: "⏎ takes the first"
                    size: 11
                    weight: 700
                    customColor: Services.Colors.accent
                }
            }
        }
    }
}
