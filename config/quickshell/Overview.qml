// Layout overview — SUPER + TAB (`qs ipc call overview toggle`).
//
// A niri-style zoomed-out map of the desktop, but drawn as a SCHEMATIC floor
// plan instead of screenshots: every non-special workspace is a card shaped
// like its monitor, and every window on it is a themed rectangle at its TRUE
// on-screen position and size, scaled to fit the card. Fast, crisp, always
// accurate, no capture. Hover a window to read its title; click it to focus
// and jump there; click a card's empty space to switch to that workspace;
// arrow keys + Enter navigate and jump; ESC closes.
//
// Structure follows the overlays Selah already has (CheatSheet / AetherPicker):
// a Variants over Quickshell.screens where only the screen that opened it
// (`Services.Overview.ownerScreen`) renders, so exactly one surface ever
// claims WlrKeyboardFocus.Exclusive — that exclusive focus is also what routes
// keys to the focus Item below. Services.Overview owns the state and geometry;
// this file only draws it.
import QtQuick
import Quickshell
import Quickshell.Wayland
import "./services" as Services

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        readonly property bool owns: Services.Overview.open
            && Services.Overview.ownerScreen !== ""
            && Services.Overview.ownerScreen === (modelData ? modelData.name : "")

        visible: owns
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: owns ? WlrKeyboardFocus.Exclusive
                                           : WlrKeyboardFocus.None
        WlrLayershell.namespace: "selah-overview"

        // re-centre the view on the freshly-reset selection each time it opens
        onOwnsChanged: if (owns) flick.centerSel()

        // ---- keyboard: Esc closes, arrows step windows/workspaces, Enter jumps ----
        // Selection lives in Services.Overview; the arrows just drive it and the
        // view pans so the picked window stays centred (see flick.centerSel).
        Item {
            id: keyHandler
            anchors.fill: parent
            focus: win.owns
            onVisibleChanged: if (visible) forceActiveFocus()

            Keys.onEscapePressed: Services.Overview.close()
            Keys.onLeftPressed:   Services.Overview.navLeft()
            Keys.onRightPressed:  Services.Overview.navRight()
            Keys.onUpPressed:     Services.Overview.navUp()
            Keys.onDownPressed:   Services.Overview.navDown()
            Keys.onReturnPressed: Services.Overview.activateSelection()
        }

        // ---- scrim: click anywhere outside a card to dismiss ----
        Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.6)
            opacity: win.owns ? 1 : 0

            Behavior on opacity {
                NumberAnimation {
                    duration: Services.Motion.effects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: Services.Overview.close()
            }
        }

        // ---- content ----
        Column {
            id: content
            anchors.fill: parent
            anchors.margins: 44
            spacing: 18
            opacity: win.owns ? 1 : 0
            scale: win.owns ? 1 : 0.96
            transformOrigin: Item.Center

            Behavior on opacity {
                NumberAnimation {
                    duration: Services.Motion.effects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }
            Behavior on scale {
                SpringAnimation {
                    spring: Services.Motion.spatialFastSpring
                    damping: Services.Motion.spatialFastDamping
                }
            }

            // ---------- header ----------
            Item {
                id: header
                width: parent.width
                height: 30

                Row {
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10

                    Text {
                        font.family: Services.Fonts.family
                        text: "Overview"
                        font.pixelSize: 15
                        font.bold: true
                        color: Services.Colors.text
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Services.Fonts.family
                        text: Services.Overview.workspaces.length + " workspaces · "
                            + Services.Overview.windowCount + " windows"
                        font.pixelSize: 12
                        color: Services.Colors.textMuted
                    }
                }

                Rectangle {   // "esc closes" hint — the way out for mouse users
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: escT.implicitWidth + 18
                    height: 24
                    radius: 7
                    color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                   Services.Colors.text.b, 0.08)
                    border.color: Services.Colors.low
                    border.width: 1

                    Text {
                        id: escT
                        anchors.centerIn: parent
                        font.family: Services.Fonts.family
                        text: "ESC"
                        font.pixelSize: 11
                        font.bold: true
                        color: Services.Colors.textMuted
                    }
                }
            }

            Rectangle {
                width: parent.width
                height: 1
                color: Services.Colors.low
                opacity: 0.4
            }

            // ---------- workspace cards ----------
            // Uniform card WIDTH fits the horizontal space; each card's HEIGHT
            // follows its own monitor's aspect ratio, stacked vertically. A
            // Flickable carries the column so many workspaces scroll instead of
            // shrinking the floor-plan past readability.
            Flickable {
                id: flick
                width: parent.width
                height: parent.height - header.height - 1 - parent.spacing * 2
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                // Horizontal room for apps that tile past the monitor edge. They
                // now trail LEFT of the box, so the strip is [trailing apps][centred
                // box][matching empty room]. Content is never narrower than the
                // viewport, so "centred" always means centred in view; the extra
                // width lets the view pan left to reach far-flung apps.
                readonly property real trailLeft: {
                    const k = monScale
                    let m = 0
                    for (const w of Services.Overview.workspaces) {
                        const monR = w.monitorX + w.monitorW
                        for (const g of w.windows) {
                            const cx = g.x + g.w / 2
                            let ext = 0
                            if (cx > monR)             // tiled past the right edge → mirrored left
                                ext = (g.x + g.w - monR) * k
                            else if (cx < w.monitorX)  // tiled off the left edge → already trails
                                ext = (w.monitorX - g.x) * k
                            m = Math.max(m, ext)
                        }
                    }
                    return m
                }
                readonly property real maxMonW: {
                    let m = 0
                    for (const w of Services.Overview.workspaces)
                        m = Math.max(m, w.monitorW * monScale)
                    return m
                }
                readonly property real contentW: Math.max(width, 2 * trailLeft + maxMonW)
                // vertical slack to centre a short card column in the viewport
                readonly property real colOffset:
                    Math.max(0, (height - cardsCol.implicitHeight) / 2)

                contentWidth: contentW
                contentHeight: Math.max(cardsCol.implicitHeight, height)
                interactive: contentHeight > height || contentWidth > width

                // Pan so the selected window (or, if none, its box) is dead-centre.
                function centerSel() {
                    const list = Services.Overview.workspaces
                    const si = Services.Overview.selWs
                    const ws = list[si]
                    if (!ws) return
                    const k = monScale
                    const monW = ws.monitorW * k
                    const monR = ws.monitorX + ws.monitorW
                    const boxX = (contentW - monW) / 2      // box left edge, content coords
                    // horizontal: centre the picked window, or the box itself
                    const g = Services.Overview.sortedWins[Services.Overview.selWin]
                    let cxContent
                    if (!g) {
                        cxContent = boxX + monW / 2
                    } else if (g.x + g.w / 2 > monR) { // off-screen right → mirrored left
                        cxContent = boxX + (monR - g.x - g.w / 2) * k
                    } else {                           // on-screen (or trailing left)
                        cxContent = boxX + (g.x - ws.monitorX + g.w / 2) * k
                    }
                    const tx = Math.max(0, Math.min(contentW - width, cxContent - width / 2))
                    // vertical: centre the selected card
                    let y = colOffset
                    for (let j = 0; j < si && j < list.length; j++)
                        y += list[j].monitorH * k + cardsCol.spacing
                    const cy = y + (ws.monitorH * k) / 2
                    const ty = Math.max(0, Math.min(contentHeight - height, cy - height / 2))

                    panX.to = tx
                    panX.start()
                    panY.to = ty
                    panY.start()
                }

                NumberAnimation {
                    id: panX; target: flick; property: "contentX"
                    duration: Services.Motion.effects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
                NumberAnimation {
                    id: panY; target: flick; property: "contentY"
                    duration: Services.Motion.effects
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }

                // follow the selection as the arrows move it
                Connections {
                    target: Services.Overview
                    function onSelWinChanged() { flick.centerSel() }
                    function onSelWsChanged()  { flick.centerSel() }
                }

                // FIXED monitor scale — independent of how many apps are open, so
                // the workspace box never resizes. Chosen so at least 2 boxes are
                // fully visible vertically (all of them if there are ≤2); extra
                // workspaces scroll. The box is centered horizontally in the card.
                readonly property real monScale: {
                    const ws = Services.Overview.workspaces
                    const mw = ws.length > 0 ? ws[0].monitorW : 1920
                    const mh = ws.length > 0 ? ws[0].monitorH : 1080
                    const n = Math.max(1, ws.length)
                    // fit min(n,2) boxes (with spacing) into the vertical space
                    const fit = Math.min(n, 2)
                    const spacing = cardsCol.spacing
                    const hFit = (flick.height - spacing * (fit - 1)) / (fit * mh)
                    // cap box width so it sits centered with room for trailing apps
                    const wFit = flick.width * 0.5 / mw
                    return Math.max(0.05, Math.min(wFit, hFit))
                }

                // full content width so each box centres within the whole strip
                Column {
                    id: cardsCol
                    width: flick.contentW
                    y: flick.colOffset
                    spacing: 28

                    Repeater {
                        model: Services.Overview.workspaces

                        delegate: Item {
                            id: card
                            required property var modelData
                            required property int index
                            readonly property var ws: modelData
                            // FIXED monitor scale so the workspace box never resizes
                            // as apps open. Card fills the viewport width so the box
                            // can be centered; it grows taller only via its own height.
                            readonly property real k: flick.monScale       // px → card scale (constant)
                            readonly property real cardW: flick.contentW
                            readonly property real cardH: ws.monitorH * k
                            // the fixed workspace box, centered horizontally in the card
                            readonly property real monW: ws.monitorW * k
                            readonly property real monH: ws.monitorH * k
                            readonly property real monX: (cardW - monW) / 2
                            readonly property real monY: 0
                            readonly property bool active:
                                Services.Overview.selWs === index || ws.focused
                            // does this card render a real capture behind its
                            // schematic outlines? Only the focused monitor was
                            // captured (Quickshell can't grab undrawn workspaces).
                            readonly property bool real:
                                ws.focused && Services.Overview.shot !== ""
                                && ws.monitor === Services.Overview.shotMonitor
                            // partition windows by whether their center sits inside the
                            // monitor viewport. On-screen ones = the current active apps
                            // (rendered inside the box, over the capture); the rest are
                            // tiled past the edge and trail OUTSIDE the box.
                            readonly property var onScreenWins: card.ws.windows.filter(w => {
                                const cx = w.x + w.w / 2
                                return cx >= card.ws.monitorX
                                    && cx <= card.ws.monitorX + card.ws.monitorW
                            })
                            readonly property var offScreenWins: card.ws.windows.filter(w => {
                                const cx = w.x + w.w / 2
                                return cx < card.ws.monitorX
                                    || cx > card.ws.monitorX + card.ws.monitorW
                            })

                            width: cardW
                            height: cardH
                            // no horizontal anchor — cards sit at the Column's left
                            // edge so all monitor rects align on the same left line

                            // whole-card empty click → switch to this workspace.
                            // Sits at the very back; the opaque box covers its own
                            // region (an in-box MouseArea handles that), while the
                            // off-screen zone to the right falls through to here.
                            MouseArea {
                                anchors.fill: parent
                                z: -1
                                onClicked: Services.Overview.switchWorkspace(card.ws.id)
                            }

                            // OFF-SCREEN apps — tiled past the monitor edge, so grim
                            // never captured them. Rendered OUTSIDE the box (children of
                            // the card, in strip coords) so they trail past its border.
                            // Always filled schematic — there are no real pixels behind.
                            Repeater {
                                model: card.offScreenWins

                                delegate: Rectangle {
                                    id: owr
                                    required property var modelData
                                    readonly property var win: modelData
                                    readonly property bool hovered: oma.containsMouse
                                    readonly property bool isFocused:
                                        win.address === Services.Overview.focusedAddress
                                    // the arrow-key pick (matches the mirrored position below)
                                    readonly property bool isSel: Services.Overview.selAddr !== ""
                                        && win.address === Services.Overview.selAddr
                                    readonly property bool hi: hovered || isSel
                                    // tiled past the RIGHT edge → drawn mirrored to the LEFT
                                    readonly property bool mirror:
                                        win.x + win.w / 2 > card.ws.monitorX + card.ws.monitorW

                                    x: mirror
                                        ? card.monX + (card.ws.monitorX + card.ws.monitorW
                                                       - win.x - win.w) * card.k
                                        : card.monX + (win.x - card.ws.monitorX) * card.k
                                    y: card.monY + (modelData.y - card.ws.monitorY) * card.k
                                    width:  Math.max(18, modelData.w * card.k)
                                    height: Math.max(14, modelData.h * card.k)
                                    radius: 7
                                    color: isFocused
                                        ? Qt.rgba(Services.Colors.accent.r,
                                                  Services.Colors.accent.g,
                                                  Services.Colors.accent.b, 0.85)
                                        : Qt.rgba(Services.Colors.surfaceAlt.r,
                                                  Services.Colors.surfaceAlt.g,
                                                  Services.Colors.surfaceAlt.b,
                                                  hi ? 0.95 : 0.75)
                                    border.color: isFocused || hi
                                        ? Services.Colors.accent : Services.Colors.low
                                    border.width: isFocused || hi ? 2 : 1
                                    z: hi ? 2 : (isFocused ? 1 : 0)

                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    Text {
                                        anchors.centerIn: parent
                                        width: parent.width - 10
                                        visible: parent.width > 46 && parent.height > 20
                                        font.family: Services.Fonts.family
                                        text: modelData.cls || modelData.title
                                        font.pixelSize: 10
                                        font.bold: true
                                        elide: Text.ElideRight
                                        horizontalAlignment: Text.AlignHCenter
                                        color: isFocused ? Qt.rgba(0, 0, 0, 0.85)
                                                         : Services.Colors.text
                                    }

                                    MouseArea {
                                        id: oma
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: Services.Overview.focusWindow(modelData.address)
                                    }
                                }
                            }

                            // THE WORKSPACE BOX — fixed to the MONITOR size, so it never
                            // resizes however many apps are open. On-screen apps live
                            // inside it; the rest trail outside (above).
                            Rectangle {
                                id: screen
                                x: card.monX; y: card.monY
                                width: card.monW; height: card.monH
                                radius: 14
                                color: Services.Colors.surface
                                border.color: card.active ? Services.Colors.accent
                                                           : Services.Colors.low
                                border.width: card.active ? 2 : 1
                                clip: true

                                Behavior on border.color { ColorAnimation { duration: 120 } }

                                // real capture fills the box exactly (box == monitor aspect)
                                Image {
                                    id: shot
                                    anchors.fill: parent
                                    source: card.real
                                        ? "file://" + Services.Overview.shot
                                          + "?" + Services.Overview.shotSeq   // bust decode cache
                                        : ""
                                    fillMode: Image.Stretch   // box is monitor-shaped, so stretch == exact fill
                                    asynchronous: true
                                    opacity: card.real && status === Image.Ready ? 1 : 0
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: Services.Motion.effects
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                        }
                                    }
                                }

                                // in-box empty click → switch to this workspace
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: Services.Overview.switchWorkspace(card.ws.id)
                                }

                                // ON-SCREEN apps — the current active windows, inside the
                                // box at monitor-relative coords. Over a real capture they
                                // become faint clickable outlines so the pixels show.
                                Repeater {
                                    model: card.onScreenWins

                                    delegate: Rectangle {
                                        id: wr
                                        required property var modelData
                                        readonly property var win: modelData
                                        readonly property bool hovered: ma.containsMouse
                                        readonly property bool isFocused:
                                            win.address === Services.Overview.focusedAddress
                                        // the arrow-key pick
                                        readonly property bool isSel: Services.Overview.selAddr !== ""
                                            && win.address === Services.Overview.selAddr
                                        readonly property bool hi: hovered || isSel

                                        x: (modelData.x - card.ws.monitorX) * card.k
                                        y: (modelData.y - card.ws.monitorY) * card.k
                                        width:  Math.max(18, modelData.w * card.k)
                                        height: Math.max(14, modelData.h * card.k)
                                        radius: 7
                                        color: card.real
                                            ? Qt.rgba(Services.Colors.accent.r,
                                                      Services.Colors.accent.g,
                                                      Services.Colors.accent.b,
                                                      hi ? 0.35 : (isFocused ? 0.22 : 0.0))
                                            : (isFocused
                                            ? Qt.rgba(Services.Colors.accent.r,
                                                      Services.Colors.accent.g,
                                                      Services.Colors.accent.b, 0.85)
                                            : Qt.rgba(Services.Colors.surfaceAlt.r,
                                                      Services.Colors.surfaceAlt.g,
                                                      Services.Colors.surfaceAlt.b,
                                                      hi ? 0.95 : 0.75))
                                        border.color: isFocused || hi
                                            ? Services.Colors.accent : Services.Colors.low
                                        border.width: isFocused || hi ? 2 : 1
                                        z: hi ? 2 : (isFocused ? 1 : 0)

                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        // app class label, only when there's room (and
                                        // not over real pixels — the content says it)
                                        Text {
                                            anchors.centerIn: parent
                                            width: parent.width - 10
                                            visible: !card.real && parent.width > 46 && parent.height > 20
                                            font.family: Services.Fonts.family
                                            text: modelData.cls || modelData.title
                                            font.pixelSize: 10
                                            font.bold: true
                                            elide: Text.ElideRight
                                            horizontalAlignment: Text.AlignHCenter
                                            color: isFocused
                                                ? Qt.rgba(0, 0, 0, 0.85)
                                                : Services.Colors.text
                                        }

                                        MouseArea {
                                            id: ma
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: Services.Overview.focusWindow(modelData.address)
                                        }
                                    }
                                }

                                // workspace name chip, top-left of the box
                                Rectangle {
                                    anchors.left: parent.left
                                    anchors.top: parent.top
                                    anchors.margins: 8
                                    width: wsChip.implicitWidth + 16
                                    height: 22
                                    radius: 7
                                    color: Qt.rgba(0, 0, 0, 0.45)

                                    Text {
                                        id: wsChip
                                        anchors.centerIn: parent
                                        font.family: Services.Fonts.family
                                        text: card.ws.name
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: Services.Colors.text
                                    }
                                }
                            }
                        }
                    }
                }

                // empty state — no workspaces at all
                Text {
                    visible: Services.Overview.workspaces.length === 0
                    anchors.centerIn: parent
                    font.family: Services.Fonts.family
                    text: "no workspaces"
                    font.pixelSize: 13
                    color: Services.Colors.textMuted
                }
            }
        }
    }
}
