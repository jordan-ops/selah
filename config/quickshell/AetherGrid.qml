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

        // Any of these can cross the prefetch line: contentY while
        // scrolling, contentHeight when a page lands, atYEnd once layout
        // settles and the grid becomes scrollable at all.
        //
        // A contentHeight move while a restore is armed means the reset is
        // still moving: re-assert and push the settle window out. A
        // contentY move on its own is either that reset's clamp — which
        // the assertions above and below still catch — or the user
        // scrolling, which must not be fought.
        onContentYChanged: root.maybeLoadMore()
        onContentHeightChanged: {
            root.maybeLoadMore()
            if (root.pendingY >= 0) {
                root.heightDirty = true
                root.restoreNow()
                settleTimer.restart()
            }
        }
        onAtYEndChanged: root.maybeLoadMore()

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

            // Selection halo, drawn in the 7px gutter the frame leaves
            // around the card so it reads as a ring around the whole cell
            // rather than as a tint on the wallpaper itself. The card's own
            // accent border alone was too easy to lose against a busy
            // image — you could not tell at a glance which one you were on.
            Rectangle {
                anchors.fill: parent
                anchors.margins: 4
                radius: 13
                color: "transparent"
                border.width: 2
                border.color: Services.Colors.accent
                opacity: cell.sel ? 0.9 : 0
                Behavior on opacity { NumberAnimation { duration: 140 } }
            }

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

                    // Position of this card in the loaded results, shown only
                    // on the selected one: the footer's "n / m" is too far
                    // from the grid to read while you are scrolling through
                    // pages. Top-right, since the theme badge owns top-left.
                    Rectangle {
                        visible: cell.sel
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        height: selT.implicitHeight + 8
                        width: selT.implicitWidth + 14
                        radius: 6
                        color: Qt.rgba(0, 0, 0, 0.72)
                        border.width: 1
                        border.color: Services.Colors.accent
                        Text {
                            id: selT
                            anchors.centerIn: parent
                            text: (cell.index + 1) + " / " + Services.Aether.viewModel.length
                            color: Services.Colors.accent
                            font.family: Services.Fonts.family
                            font.pixelSize: 11
                        }
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

    // ==================================================================
    // infinite scroll
    // ==================================================================
    // A page costs ~2 s end to end and almost all of it is network to
    // wallhaven.cc (aether itself burns ~0.15 s CPU), so waiting until the
    // viewport is literally at the tail — what this did before — leaves the
    // user parked on a static screen for two seconds. The next page is
    // therefore asked for while there is still about a screen of results
    // left to scroll through, and is usually landing by the time the bottom
    // is reached. The first page being too short to scroll still counts as
    // "at the end", so it keeps pulling until the grid fills.
    readonly property real prefetchScreens: 1.0

    // Cheap and safe to fire from every signal below: whMore() drops the
    // call while a fetch is in flight and stops at whLastPage, and each
    // page is taller than the margin, so this cannot run away and page
    // through the whole catalogue on its own.
    function maybeLoadMore() {
        if (Services.Aether.view !== "wallhaven") return
        const toEnd = grid.contentHeight - grid.contentY - grid.height
        if (toEnd <= grid.height * root.prefetchScreens) Services.Aether.whMore()
    }

    // ==================================================================
    // scroll preservation across rebuilds
    // ==================================================================
    // `viewModel` is a plain JS array, so assigning a new one is a model
    // RESET: every delegate is destroyed, contentHeight collapses, the
    // clamp drags contentY down to 0 — and the page that just landed then
    // appears under a viewport pinned at the top. That is the
    // "scrollbar jumps all the way back when new images load" bug.
    //
    // rebuildModel() brackets the assignment with two signals, so the
    // offset is snapshotted while the old delegates are still alive.
    // Only an append restores: a new search, an opened group or a view
    // switch should start at the top, which is why isAppend comes from
    // the service instead of being guessed from the item count.
    //
    // The restore is re-asserted from SEVERAL places on purpose. A reset
    // does not clamp contentY exactly once — it can zero it while the old
    // height is still being reported, then clamp again as the new height
    // arrives — and an early single write disarmed the guard, so the
    // later clamp won and the view landed on page 1 anyway (which is
    // exactly what was still being reported). Height changes extend the
    // settle window; when they stop, the user owns the scroll again.
    // There is deliberately no restore from onContentYChanged: that
    // would fight a genuine scroll.
    property real pendingY: -1        // offset to put back, -1 = disarmed
    property bool heightDirty: false  // contentHeight moved while armed

    function restoreNow() {
        if (root.pendingY < 0) return
        // collapse still in progress — the contentHeight handler retries
        if (grid.contentHeight <= 0) return
        const maxY = Math.max(0, grid.contentHeight - grid.height)
        const target = Math.min(root.pendingY, maxY)
        if (Math.abs(grid.contentY - target) > 1) grid.contentY = target
    }

    // Closes the window a beat after the last height change: until then
    // the reset may still be moving, afterwards the position is the
    // user's. A final assertion runs first, but only if heights actually
    // moved since we armed — that is the signature of a reset, whereas
    // quiet heights mean any offset difference is the user's own doing.
    Timer {
        id: settleTimer
        interval: 200
        onTriggered: {
            if (root.pendingY < 0) return
            if (root.heightDirty) root.restoreNow()
            root.pendingY = -1
            root.heightDirty = false
        }
    }

    Connections {
        target: Services.Aether

        // A page request just settled: re-run the prefetch check. This is
        // what the old blind whMorePending replay did, except now the
        // margin is re-applied instead of fetching unconditionally.
        function onWhMoreSettled() { root.maybeLoadMore() }

        // Fires BEFORE viewModel is reassigned, so contentY is still the
        // real, unclamped offset here.
        function onAboutToRebuild(isAppend) {
            root.pendingY = isAppend && grid.contentY > 0 ? grid.contentY : -1
            root.heightDirty = false
        }
        function onRebuildSettled() {
            if (root.pendingY < 0) return
            root.restoreNow()
            Qt.callLater(root.restoreNow)   // second pass if layout was still pending
            settleTimer.restart()
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

    // Page-in-flight pill: a fetch is ~2 s of network and the footer's
    // "searching wallhaven ..." is easy to miss once the eye is down in
    // the grid. Anchored to the grid rather than the content, so it stays
    // put while the tail lands underneath it. Hidden while the grid is
    // empty — the centred hint above already says why in that case.
    Rectangle {
        readonly property bool isAppend: Services.Aether.whAppending
        visible: Services.Aether.view === "wallhaven"
              && Services.Aether.whSearching
              && Services.Aether.viewModel.length > 0
        anchors.horizontalCenter: grid.horizontalCenter
        anchors.bottom: grid.bottom
        anchors.bottomMargin: 12
        height: pillT.implicitHeight + 10
        width: pillT.implicitWidth + 20
        radius: 7
        color: Qt.rgba(0, 0, 0, 0.62)
        border.width: 1
        border.color: Qt.rgba(Services.Colors.low.r, Services.Colors.low.g,
                              Services.Colors.low.b, 0.55)
        Text {
            id: pillT
            anchors.centerIn: parent
            text: parent.isAppend
                ? "loading page " + (Services.Aether.whPage + 1) + " ..."
                : "searching wallhaven ..."
            color: Services.Colors.text
            font.family: Services.Fonts.family
            font.pixelSize: 11
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

