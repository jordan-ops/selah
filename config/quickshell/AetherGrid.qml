import QtQuick
import "./services" as Services

// The wallpaper grid shared by all three views: theme groups, the standalone
// local library, and wallhaven results. It reads Aether.viewModel and knows
// nothing about where the items came from — the only difference it draws is
// the `kind` field (a group card shows its wallpaper count, a wallpaper card
// shows which theme it already belongs to, if any).
//
// interactive stays on (it defaults to): that is what makes the mouse wheel
// scroll the grid, which the old carousel did not do at all.
Item {
    id: root

    property string emptyHint: "nothing here"
    property string loadingHint: "scanning ..."

    readonly property int columns: Math.max(2, Math.floor(width / 236))
    readonly property int cellW: Math.max(160, Math.floor(width / columns))
    readonly property int cellH: Math.round(cellW * 0.60) + 34

    GridView {
        id: grid
        anchors.fill: parent
        clip: true
        model: Services.Aether.viewModel
        currentIndex: Services.Aether.currentIndex
        cellWidth: root.cellW
        cellHeight: root.cellH
        // Keys are handled one level up so the search box and the grid share
        // a single handler; letting GridView eat them would split the flow.
        keyNavigationEnabled: false
        boundsBehavior: Flickable.StopAtBounds

        // No QtQuick.Controls in this config, so the scrollbar is drawn by
        // hand below rather than pulled in from a widget library.

        delegate: Item {
            id: cell
            required property int index
            width: grid.cellWidth
            height: grid.cellHeight

            readonly property var it: Services.Aether.viewModel[cell.index] ?? null
            readonly property bool sel: cell.index === Services.Aether.currentIndex
            readonly property bool isGroup: it && it.kind === "group"

            // Keep the selected card in view when it moves off-screen (arrow
            // keys, filter re-sort, new search results landing).
            Connections {
                target: Services.Aether
                function onCurrentIndexChanged() {
                    if (cell.sel) grid.positionViewAtIndex(cell.index, GridView.Contain)
                }
            }

            Item {
                id: frame
                anchors.fill: parent
                anchors.margins: 7

                Rectangle {
                    anchors.fill: parent
                    radius: 10
                    color: Services.Colors.surface
                    border.width: cell.sel ? 2 : 1
                    border.color: cell.sel ? Services.Colors.accent
                        : Qt.rgba(Services.Colors.low.r, Services.Colors.low.g,
                                  Services.Colors.low.b, hover.hovered ? 0.9 : 0.45)
                    Behavior on border.color { ColorAnimation { duration: 120 } }
                    clip: true

                    Image {
                        id: img
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.bottom: labelBar.top
                        source: cell.it ? Services.Aether.fileUrl(cell.it.preview) : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        // Cap the decode: these are 4–6 K wallpapers, and only
                        // the size actually drawn should ever be in memory.
                        sourceSize.width: cell.sel ? 640 : 360
                    }

                    // Count for a group, theme badge for a wallpaper that
                    // already lives in one — the two things you scan for.
                    Rectangle {
                        visible: cell.isGroup || (cell.it && cell.it.sub !== "")
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.margins: 8
                        height: badgeT.implicitHeight + 8
                        width: badgeT.implicitWidth + 14
                        radius: 6
                        color: Qt.rgba(0, 0, 0, 0.62)
                        Text {
                            id: badgeT
                            anchors.centerIn: parent
                            text: cell.isGroup ? cell.it.sub
                                : "in " + cell.it.sub
                            color: Services.Colors.text
                            font.family: Services.Fonts.family
                            font.pixelSize: 11
                        }
                    }

                    Rectangle {
                        id: labelBar
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: 30
                        color: Services.Colors.surfaceAlt
                        Text {
                            font.family: Services.Fonts.family
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 9
                            anchors.rightMargin: 9
                            text: cell.it ? cell.it.title : ""
                            color: Services.Colors.text
                            font.pixelSize: 12
                            elide: Text.ElideMiddle
                        }
                    }
                }

                HoverHandler { id: hover }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    // First click lands the selection (and opens a group, since
                    // there is nothing to "select" inside a closed one); a
                    // second click on the same card, or a double click, acts.
                    onClicked: {
                        if (!cell.it) return
                        if (cell.isGroup) {
                            Services.Aether.openGroup(cell.it.theme)
                        } else if (cell.sel) {
                            Services.Aether.activate()
                        } else {
                            Services.Aether.select(cell.index)
                        }
                    }
                    onDoubleClicked: Services.Aether.activate()
                }
            }
        }
    }

    // Empty / loading states — "no items" must always say WHY. Sibling of the
    // GridView: a child of a Flickable scrolls with the content, which would
    // send the hint off-screen on an empty grid.
    Column {
        anchors.centerIn: grid
        spacing: 8
        visible: Services.Aether.viewModel.length === 0
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: !Services.Aether.listLoaded ? root.loadingHint : root.emptyHint
            color: Services.Colors.textMuted
            font.family: Services.Fonts.family
            font.pixelSize: 14
        }
        Text {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: Services.Aether.listError !== ""
            text: Services.Aether.listError
            color: Services.Colors.critical
            font.family: Services.Fonts.family
            font.pixelSize: 12
        }
    }

    // Hand-rolled scrollbar (this config uses no QtQuick.Controls).
    Rectangle {
        visible: grid.contentHeight > grid.height + 4
        anchors.right: grid.right
        width: 5
        height: Math.max(30, grid.height * grid.height / grid.contentHeight)
        radius: 3
        color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                       Services.Colors.text.b, 0.22)
        // grid fills this item, so root coordinates == grid coordinates.
        y: grid.height > 0
           ? (grid.height - height) * Math.max(0, Math.min(1, grid.contentY
               / Math.max(1, grid.contentHeight - grid.height)))
           : 0
    }
}
