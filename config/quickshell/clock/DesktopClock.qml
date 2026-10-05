import QtQuick
import "../services" as Services

// The desktop clock widget: the giant time in a box you can put where
// you like. Double-click the box to enter edit mode (border + resize
// handle appear), drag to move, drag the corner to resize, click
// anywhere else on the desktop to leave — geometry is written to
// settings.json in ONE batch on the way out (Settings.setAll, so four
// numbers can't race the writer).
//
// The box reads its geometry from Settings.clockBox() and writes it back
// to the same keys, which is what makes the Clock lock style show the
// thing you placed: lock/Clock.qml asks clockBox() too, with the space
// it needs for the prompt reserved below.
//
// Ported from NibrasShell's desktop/DesktopClock.qml + Widgets.qml —
// their double-click edit model and drag math, minus ThemeManager: this
// saves straight to our settings store instead of into a theme JSON.
Item {
    id: root

    // Geometry is owned by this item after creation: initialised from
    // settings, moved by the drag, written back on endEdit(). While not
    // editing, an external change (another screen's drag, `qs ipc call
    // settings set clock.x …`, a reload) is pulled back in.
    function loadBox() {
        const b = Services.Settings.clockBox(root.screenW, root.screenH, 0)
        root.x = b.x
        root.y = b.y
        root.width = b.width
        root.height = b.height
    }

    // the surface we live on = the wallpaper window = full screen
    readonly property real screenW: parent ? parent.width : 1920
    readonly property real screenH: parent ? parent.height : 1080

    function clampBox() {
        width = Math.max(200, Math.min(width, screenW))
        height = Math.max(80, Math.min(height, screenH))
        x = Math.max(0, Math.min(x, screenW - width))
        y = Math.max(0, Math.min(y, screenH - height))
    }

    property bool editMode: false

    // called by Background's click-away layer (the box can't see outside
    // itself, so leaving edit mode is a two-part handshake)
    function endEdit() {
        if (!root.editMode) return
        root.editMode = false
        root.clampBox()
        Services.Settings.setAll({
            "clock.x": Math.round(root.x),
            "clock.y": Math.round(root.y),
            "clock.w": Math.round(root.width),
            "clock.h": Math.round(root.height)
        })
    }

    Component.onCompleted: loadBox()

    Connections {
        target: Services.Settings
        // any external write — including our own setAll on the way out
        // of edit mode — re-reads the box, so every screen converges on
        // the same geometry without a reload
        function onValuesChanged() {
            if (!root.editMode) root.loadBox()
        }
    }

    // ——— edit-mode chrome ———
    Rectangle {
        anchors.fill: parent
        visible: root.editMode
        color: Services.Colors.background
        opacity: 0.2
        border.width: 2
        border.color: Services.Colors.accent
    }

    GiantClock {
        anchors.fill: parent
        format: Services.Settings.clockFormat
        glow: Services.Settings.clockGlow
        color: Services.Colors.text
    }

    // ——— move / resize ———
    MouseArea {
        id: dragArea
        anchors.fill: parent
        z: 1
        cursorShape: root.editMode ? Qt.SizeAllCursor : Qt.ArrowCursor
        property real px0: 0
        property real py0: 0
        property real ox: 0
        property real oy: 0

        // double-click toggles edit mode — outside it the box swallows
        // the click and does nothing (no accidental drags, no ripple
        // firing underneath the widget)
        onDoubleClicked: {
            if (root.editMode) root.endEdit()
            else root.editMode = true
        }

        onPressed: mouse => {
            if (!root.editMode) return
            const p = dragArea.mapToItem(root.parent, mouse.x, mouse.y)
            dragArea.px0 = p.x
            dragArea.py0 = p.y
            dragArea.ox = root.x
            dragArea.oy = root.y
        }
        onPositionChanged: mouse => {
            if (!dragArea.pressed || !root.editMode) return
            const p = dragArea.mapToItem(root.parent, mouse.x, mouse.y)
            root.x = dragArea.ox + (p.x - dragArea.px0)
            root.y = dragArea.oy + (p.y - dragArea.py0)
            root.clampBox()
        }
    }

    Rectangle {
        id: handle
        visible: root.editMode
        width: 22
        height: 22
        radius: 11
        color: Services.Colors.accent
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: -11   // straddles the corner, like theirs
        z: 2

        MouseArea {
            id: handleMouse
            anchors.fill: parent
            cursorShape: Qt.SizeFDiagCursor
            property real px0: 0
            property real py0: 0
            property real w0: 0
            property real h0: 0
            onPressed: mouse => {
                const p = handleMouse.mapToItem(root.parent, mouse.x, mouse.y)
                handleMouse.px0 = p.x
                handleMouse.py0 = p.y
                handleMouse.w0 = root.width
                handleMouse.h0 = root.height
            }
            onPositionChanged: mouse => {
                if (!pressed) return
                const p = handleMouse.mapToItem(root.parent, mouse.x, mouse.y)
                root.width = handleMouse.w0 + (p.x - handleMouse.px0)
                root.height = handleMouse.h0 + (p.y - handleMouse.py0)
                root.clampBox()
            }
        }
    }
}
