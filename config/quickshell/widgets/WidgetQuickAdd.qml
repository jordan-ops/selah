// Ported from Nebula's Widgets/WidgetQuickAdd.qml (GPL-3.0) — qs.modules imports
// dropped: SettingsConfig, GlobalStates, Colors, M3Motion, PreviewData,
// WallpaperTheme, WidgetCatalog/Host/DesignStage and the kit are all
// siblings in widgets/ now.
pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent

    readonly property int col: GlobalStates.widgetQuickAdd.x
    readonly property int halfRow: GlobalStates.widgetQuickAdd.y
    readonly property bool open: GlobalStates.widgetEditMode && root.col >= 0

    visible: root.open
    enabled: root.open

    property string filter: ""
    onOpenChanged: if (!root.open) root.filter = ""

    readonly property real sc: GlobalStates.widgetStageScale
    readonly property point org: GlobalStates.widgetStageOrigin
    readonly property real cellX: root.org.x + (WidgetSizes.originX + root.col * WidgetSizes.pitch) * root.sc
    readonly property real cellY: root.org.y + (WidgetSizes.originY + root.halfRow * WidgetSizes.rowStep) * root.sc
    readonly property real cellSide: WidgetSizes.cell * root.sc
    readonly property rect canvasRect: Qt.rect(root.org.x, root.org.y,
                                               GlobalStates.widgetScreenSize.x * root.sc,
                                               GlobalStates.widgetScreenSize.y * root.sc)

    readonly property real popX: {
        const w = popup.implicitWidth > 0 ? popup.implicitWidth : 312
        const minX = root.canvasRect.x + 8
        const maxX = root.canvasRect.x + root.canvasRect.width - w - 8
        const right = root.cellX + root.cellSide + 14
        const left = root.cellX - 14 - w
        if (right <= maxX)
            return right
        if (left >= minX)
            return left
        return Math.max(minX, Math.min(maxX, right))
    }

    readonly property real popY: {
        const h = popup.implicitHeight > 0 ? popup.implicitHeight : 380
        const minY = root.canvasRect.y + 8
        const maxY = root.canvasRect.y + root.canvasRect.height - h - 8
        return Math.max(minY, Math.min(maxY, root.cellY - 10))
    }

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
        x: root.cellX
        y: root.cellY
        width: root.cellSide
        height: root.cellSide
        radius: 16 * root.sc
        color: Qt.alpha(Colors.primary, 0.16)
        border.width: 1
        border.color: Colors.primary

        MaterialIconSymbol {
            anchors.centerIn: parent
            content: "add"
            iconSize: Math.max(12, 20 * root.sc)
            customColor: Colors.primary
        }
    }

    Loader {
        id: popup
        active: root.open
        visible: popup.active
        x: root.popX
        y: root.popY
        sourceComponent: card
    }

    Component {
        id: card

        MotionEnter {
            dx: -8
            dy: 8
            fromScale: 0.94
            speed: "fast"

            Rectangle {
                implicitWidth: 312
                implicitHeight: body.implicitHeight + 28
                radius: 26
                color: Colors.surfaceContainer
                border.width: 1
                border.color: Qt.alpha(Colors.outline, 0.24)

                ColumnLayout {
                    id: body
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 10

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 2
                        spacing: 6

                        CustomText {
                            Layout.fillWidth: true
                            content: "ADD HERE · COL " + (root.col + 1) + ", ROW " + (Math.floor(root.halfRow / 2) + 1)
                            size: 10
                            weight: 700
                            customColor: Colors.primary
                            font.letterSpacing: 1.3
                        }

                        MaterialIconSymbol {
                            content: "close"
                            iconSize: 15
                            customColor: Colors.outline

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
                        color: Colors.surfaceContainerHigh
                        border.width: 1
                        border.color: quickInput.activeFocus ? Qt.alpha(Colors.primary, 0.7) : "transparent"

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            MaterialIconSymbol {
                                content: "search"
                                iconSize: 15
                                customColor: Colors.outline
                            }

                            TextInput {
                                id: quickInput
                                Layout.fillWidth: true
                                clip: true
                                text: root.filter
                                font.family: SettingsConfig.general.defaultFont ?? "Rubik"
                                font.pixelSize: 12
                                font.weight: 500
                                color: Colors.surfaceText
                                selectionColor: Qt.alpha(Colors.primary, 0.4)
                                selectedTextColor: Colors.surfaceText
                                verticalAlignment: TextInput.AlignVCenter
                                onTextChanged: root.filter = quickInput.text
                                onActiveFocusChanged: GlobalStates.widgetTextFocus = quickInput.activeFocus
                                Component.onCompleted: quickInput.forceActiveFocus()
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
                                    customColor: Colors.outline
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
                                radius: 16
                                color: hit.index === 0 ? Colors.surfaceContainerHigh
                                    : hitRipple.containsMouse ? Qt.alpha(Colors.surfaceContainerHigh, 0.6)
                                    : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 9
                                    anchors.rightMargin: 12
                                    spacing: 10

                                    Rectangle {
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        radius: 12
                                        color: hit.index === 0 ? Colors.surfaceContainerHighest : Colors.surfaceContainer

                                        MaterialIconSymbol {
                                            anchors.centerIn: parent
                                            content: hit.modelData.glyph
                                            iconSize: 16
                                            customColor: hit.index === 0 ? Colors.primary : Colors.outline
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
                                        }

                                        CustomText {
                                            Layout.fillWidth: true
                                            content: hit.modelData.section
                                            size: 11
                                            customColor: Colors.outline
                                        }
                                    }

                                    MaterialIconSymbol {
                                        content: hit.index === 0 ? "keyboard_return" : "add"
                                        iconSize: 15
                                        customColor: hit.index === 0 ? Colors.primary : Colors.outline
                                    }
                                }

                                RippleEffect {
                                    id: hitRipple
                                    anchors.fill: parent
                                    radius: 16
                                    hoverColor: Qt.alpha(Colors.primary, 0.07)
                                    rippleColor: Qt.alpha(Colors.primary, 0.16)
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
                                customColor: Colors.outline
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
                            customColor: Colors.outline
                        }

                        CustomText {
                            content: "⏎ takes the first"
                            size: 11
                            weight: 700
                            customColor: Colors.primary
                        }
                    }
                }
            }
        }
    }
}
