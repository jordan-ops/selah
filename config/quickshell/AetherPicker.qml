// Aether wallpaper + palette overlay for vanilla quickshell.
//
// Ported from omacom/aether's contrib/quickshell plugins (MIT) and then
// restructured to follow the official aether app's layout instead of the
// contrib carousel, because a carousel could not carry what this needs to:
//
//   · Themes are shown GROUPED (gruvbox's six wallpapers are one card that
//     opens), so the library is never one flat pile of every theme's images.
//   · Wallhaven lives in the same window — search box plus toplist/latest/
//     random/... chips — exactly like aether's WallhavenFilters.
//   · The colour edits are here too: aether's 12 sliders (saturation,
//     vibrance, ...), its 23 extraction modes and its 38 palette presets.
//   · Two explicit actions instead of one hidden Enter: Create, and
//     Create + apply (the default, what Enter runs).
//
// What replaced the omarchy plugin host: `manifest.json` + shell.toggle/hide
// became this file's own PanelWindow driven by `qs ipc call aether`, and
// `Color.*` became this setup's Services.Colors.
//
// Controls:
//   arrows / pgup / pgdn / home / end   move the selection
//   enter                               create the theme AND apply it
//   ctrl+enter                          create only (leave the desktop alone)
//   a..z, backspace                     filter / search (live, in the box)
//   ctrl+1 / 2 / 3                      Themes | Local | Wallhaven
//   ctrl+l                              light / dark palette
//   ctrl+r                              rescan
//   esc                                 back: add-mode -> group -> close
//   f2 / del                            rename / delete the selected theme
//                                        (Delete asks once, then acts)
//
// Structure mirrors Bar.qml: a Variants over Quickshell.screens, each screen
// getting its own window, and only the screen that opened it renders — the
// ownerScreen bookkeeping lives in services/Aether.qml alongside `open`.
import Quickshell
import Quickshell.Wayland
import QtQuick
import "./services" as Services

Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win
        required property var modelData
        screen: modelData

        // Multi-monitor: exactly one screen shows the overlay, the one that
        // had focus when it opened. Without this every screen would claim the
        // surface and they would fight over WlrKeyboardFocus.Exclusive.
        // Bound to modelData, not `screen`: reading `screen` from a binding
        // that also drives `visible` makes quickshell re-evaluate both against
        // each other and it reports a binding loop for `owns`.
        readonly property bool owns: Services.Aether.open
            && Services.Aether.ownerScreen !== ""
            && Services.Aether.ownerScreen === (modelData ? modelData.name : "")

        visible: owns
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        // Full-screen overlay: never reserves space for the bar.
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: owns ? WlrKeyboardFocus.Exclusive
                                           : WlrKeyboardFocus.None
        WlrLayershell.namespace: "aether-picker"

        readonly property var aether: Services.Aether
        readonly property color bg: Services.Colors.background
        readonly property color fg: Services.Colors.text
        readonly property color dim: Services.Colors.textMuted
        readonly property color accent: Services.Colors.accent
        readonly property color hairline: Services.Colors.low

        // --- rename / delete state --------------------------------------
        // The target is captured when the button is pressed, not read back at
        // commit time, so moving the cursor mid-rename can never act on a
        // different theme than the one the field was showing.
        property bool renaming: false
        property string renameFrom: ""
        property string renameDraft: ""
        property string confirmDelete: ""

        function beginRename() {
            const n = win.aether.targetGroup()
            if (n === "") return
            confirmDelete = ""
            disarm.stop()
            renameFrom = n
            renameDraft = n
            renaming = true
        }
        function cancelRename() {
            if (!renaming) return
            renaming = false
            renameFrom = ""
            renameDraft = ""
        }
        function commitRename() {
            if (!renaming) return
            const from = renameFrom, to = renameDraft
            cancelRename()
            win.aether.renameTheme(from, to)
        }
        // First press arms (and the label names the theme), second confirms.
        function armDelete() {
            const n = win.aether.targetGroup()
            if (n === "") return
            if (confirmDelete === n) {
                confirmDelete = ""
                disarm.stop()
                win.aether.deleteTheme(n)
                return
            }
            cancelRename()
            confirmDelete = n
            disarm.restart()
        }
        function resetActions() {
            if (confirmDelete !== "") { confirmDelete = ""; disarm.stop() }
            cancelRename()
        }

        Timer {
            id: disarm
            interval: 4000
            repeat: false
            onTriggered: win.confirmDelete = ""
        }

        Connections {
            // Navigating away mid-action must drop it, otherwise the armed
            // Delete button keeps naming a theme the cursor has left behind.
            target: win.aether
            function onCurrentIndexChanged() { win.resetActions() }
            function onViewChanged() { win.resetActions() }
            function onGroupOpenChanged() { win.resetActions() }
            function onAddThemeChanged() { win.resetActions() }
        }


        Item {
            id: picker
            anchors.fill: parent
            focus: win.owns
            onVisibleChanged: if (visible) forceActiveFocus()

            // --- keyboard -------------------------------------------------
            Keys.onPressed: (e) => {
                const aether = win.aether
                const k = e.key
                const mod = e.modifiers
                const ctrl = mod & Qt.ControlModifier
                const nav = grid.columns

                if (win.renaming) {
                    // The rename field takes these itself when it has focus;
                    // this is the safety net for when it does not, and it must
                    // run before the Escape/backspace branches below or Esc
                    // would back out of the picker instead of cancelling.
                    if (k === Qt.Key_Escape) { e.accepted = true; win.cancelRename(); return }
                    if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                        e.accepted = true; win.commitRename(); return
                    }
                    if (k === Qt.Key_Backspace) {
                        e.accepted = true
                        win.renameDraft = win.renameDraft.slice(0, -1)
                        return
                    }
                    const t = e.text
                    if (t && t.length === 1 && t.charCodeAt(0) > 32
                            && t.charCodeAt(0) !== 127
                            && !(mod & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))) {
                        e.accepted = true
                        win.renameDraft += t
                    }
                    return
                }
                if (win.confirmDelete !== "" && k === Qt.Key_Escape) {
                    e.accepted = true; win.resetActions(); return
                }
                if (k === Qt.Key_Escape) {
                    e.accepted = true; aether.goBack(); return
                }
                if (k === Qt.Key_F2) { e.accepted = true; win.beginRename(); return }
                if (k === Qt.Key_Delete) { e.accepted = true; win.armDelete(); return }
                if (ctrl && k >= Qt.Key_1 && k <= Qt.Key_3) {
                    e.accepted = true
                    aether.setView(k === Qt.Key_1 ? "themes"
                            : k === Qt.Key_2 ? "local" : "wallhaven")
                    return
                }
                if (ctrl && k === Qt.Key_L) { e.accepted = true; aether.toggleLight(); return }
                if (ctrl && k === Qt.Key_R) { e.accepted = true; aether.refresh(); return }
                if (ctrl && k === Qt.Key_W) {   // legacy bind: cycle the views
                    e.accepted = true
                    aether.setView(aether.view === "themes" ? "local"
                            : aether.view === "local" ? "wallhaven" : "themes")
                    return
                }
                if (k === Qt.Key_Return || k === Qt.Key_Enter) {
                    e.accepted = true
                    if (ctrl) aether.create(false)      // ctrl+enter = create only
                    else if (aether.view === "wallhaven") aether.activate()
                    else aether.activate()
                    return
                }
                if (k === Qt.Key_Left)  { e.accepted = true; aether.move(-1); return }
                if (k === Qt.Key_Right) { e.accepted = true; aether.move(1);  return }
                if (k === Qt.Key_Up)    { e.accepted = true; aether.move(-nav); return }
                if (k === Qt.Key_Down)  { e.accepted = true; aether.move(nav); return }
                if (k === Qt.Key_Home) { e.accepted = true; aether.select(0); return }
                if (k === Qt.Key_End)  { e.accepted = true; aether.select(aether.viewModel.length - 1); return }
                if (k === Qt.Key_PageUp)   { e.accepted = true; aether.move(-nav * 3); return }
                if (k === Qt.Key_PageDown) { e.accepted = true; aether.move(nav * 3);  return }
                if (k === Qt.Key_Backspace) {
                    e.accepted = true
                    if (ctrl) aether.setFilter("")
                    else aether.setFilter(aether.filter.slice(0, -1))
                    return
                }
                const ch = e.text
                if (ch && ch.length === 1
                        && !(mod & (Qt.ControlModifier | Qt.MetaModifier | Qt.AltModifier))) {
                    const code = ch.charCodeAt(0)
                    if (code > 32 && code !== 127) {     // printable only
                        e.accepted = true
                        aether.setFilter(aether.filter + ch)
                    }
                }
            }

            // --- scrim ----------------------------------------------------
            // Dim, not hide: the panel below is opaque, so the desktop reads
            // as context rather than as competition (the old 90 % scrim left
            // terminal text perfectly legible behind the cards).
            Rectangle {
                anchors.fill: parent
                color: Qt.rgba(0, 0, 0, 0.86)
            }

            // --- panel ----------------------------------------------------
            Rectangle {
                id: panel
                anchors.centerIn: parent
                width: Math.min(parent.width - 72, 1780)
                height: Math.min(parent.height - 72, 946)
                radius: 16
                color: win.bg
                border.color: win.hairline
                border.width: 1
                clip: true

                // ---------- header ----------
                Item {
                    id: header
                    anchors.top: parent.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 16
                    height: 34

                    Row {
                        id: leftCluster
                        height: parent.height
                        spacing: 10

                        // Back / breadcrumb — the way out of a group or an
                        // "add to theme" run, for people who never find esc.
                        Rectangle {
                            visible: win.aether.addTheme !== "" || win.aether.groupOpen
                            width: backT.implicitWidth + 22
                            height: 34
                            radius: 8
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                           Services.Colors.text.b, 0.08)
                            border.color: Services.Colors.low
                            border.width: 1
                            Text {
                                id: backT
                                anchors.centerIn: parent
                                text: win.aether.addTheme !== ""
                                    ? "✕ cancel add" : "‹ " + win.aether.groupTheme
                                color: Services.Colors.text
                                font.family: Services.Fonts.family
                                font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.aether.goBack()
                            }
                        }

                        Row {
                            height: parent.height
                            spacing: 4
                            Repeater {
                                model: [
                                    { l: "Themes",    v: "themes" },
                                    { l: "Local",     v: "local" },
                                    { l: "Wallhaven", v: "wallhaven" }
                                ]
                                delegate: Rectangle {
                                    required property var modelData
                                    width: segT.implicitWidth + 26
                                    height: 34
                                    radius: 8
                                    readonly property bool on: win.aether.view === modelData.v
                                    color: on ? Services.Colors.accent
                                        : Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                                  Services.Colors.text.b, 0.08)
                                    border.color: on ? Services.Colors.accent
                                                     : Services.Colors.low
                                    border.width: 1
                                    Text {
                                        id: segT
                                        anchors.centerIn: parent
                                        text: modelData.l
                                        color: on ? Services.Colors.background
                                                  : Services.Colors.textMuted
                                        font.family: Services.Fonts.family
                                        font.pixelSize: 12
                                        font.bold: on
                                    }
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: win.aether.setView(modelData.v)
                                    }
                                }
                            }
                        }
                    }

                    // Search box: always visible and always live — typing
                    // anywhere lands here, so it doubles as the caret.
                    Rectangle {
                        id: searchBox
                        anchors.right: closeBtn.left
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        width: 340
                        height: 34
                        radius: 8
                        color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                       Services.Colors.text.b, 0.08)
                        border.color: win.aether.filter !== "" || picker.activeFocus
                            ? win.accent : Services.Colors.low
                        border.width: 1
                        Text {
                            font.family: Services.Fonts.family
                            id: mag
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: "⌕"
                            color: Services.Colors.textMuted
                            font.pixelSize: 14
                        }
                        Text {
                            anchors.left: mag.right
                            anchors.leftMargin: 8
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.aether.view === "wallhaven"
                                ? (win.aether.filter !== "" ? win.aether.filter : "search wallhaven ...")
                                : (win.aether.filter !== "" ? win.aether.filter
                                    : "type to filter ...")
                            color: win.aether.filter !== "" ? Services.Colors.text
                                                       : Services.Colors.textMuted
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                            elide: Text.ElideRight
                        }
                        // caret sits at the end of what has been typed; the
                        // hidden Text below is what measures it.
                        Item {
                            id: caretHolder
                            anchors.left: mag.right
                            anchors.leftMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: measure.width
                            Text {
                                id: measure
                                text: win.aether.filter
                                font.family: Services.Fonts.family
                                font.pixelSize: 12
                                visible: false
                            }
                            Rectangle {
                                visible: picker.activeFocus
                                x: caretHolder.width
                                anchors.verticalCenter: parent.verticalCenter
                                width: 1
                                height: 16
                                color: win.accent
                            }
                        }
                    }

                    Text {
                        anchors.right: searchBox.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        text: win.aether.viewModel.length
                            + (win.aether.view === "wallhaven"
                               && win.aether.whTotal > 0
                               ? " of " + win.aether.whTotal : "")
                        color: Services.Colors.textMuted
                        font.family: Services.Fonts.family
                        font.pixelSize: 12
                    }

                    Rectangle {
                        id: closeBtn
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: 34; height: 34; radius: 8
                        color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                       Services.Colors.text.b, 0.08)
                        border.color: Services.Colors.low
                        border.width: 1
                        Text {
                            font.family: Services.Fonts.family
                            anchors.centerIn: parent
                            text: "✕"
                            color: Services.Colors.textMuted
                            font.pixelSize: 13
                        }
                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: win.aether.dismiss()
                        }
                    }
                }

                Rectangle {
                    id: line1
                    anchors.top: header.bottom
                    anchors.topMargin: 16
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: win.hairline
                    opacity: 0.45
                }

                // ---------- toolbar (context row above the grid) ----------
                Item {
                    id: toolbar
                    anchors.top: line1.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    // Only the group actions and the explanatory captions (and
                    // the whole wallhaven filter strip) belong up here — an
                    // empty toolbar would otherwise still eat a 40 px row.
                    readonly property bool hasContent:
                          (win.aether.groupOpen && win.aether.addTheme === "")
                        || (win.aether.view === "themes" && !win.aether.groupOpen && win.aether.addTheme === "")
                        || (win.aether.view === "local")
                        || (win.aether.view === "wallhaven")
                    height: hasContent ? 40 : 0
                    visible: hasContent
                    // Rename / Delete only ever target a theme, so they are
                    // absent from Local and wallhaven, and from add-mode where
                    // the footer already owns the buttons.
                    readonly property bool showThemeActions:
                          win.aether.view === "themes" && win.aether.addTheme === ""
                        && win.aether.targetGroup() !== ""

                    Row {
                        id: toolbarRow
                        height: parent.height
                        spacing: 6

                        // --- inside a theme group: add wallpapers to it ---
                        Text {
                            visible: win.aether.groupOpen && win.aether.addTheme === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.aether.groupTheme + "  ·  click a wallpaper, then Create, "
                                + "or add another one:"
                            color: Services.Colors.textMuted
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                        }
                        Repeater {
                            model: win.aether.groupOpen && win.aether.addTheme === ""
                                ? [{ l: "+ from Wallpapers", v: "local" },
                                   { l: "+ from Wallhaven",  v: "wallhaven" }]
                                : []
                            delegate: Rectangle {
                                required property var modelData
                                width: addT.implicitWidth + 20
                                height: 28
                                radius: 7
                                color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                               Services.Colors.text.b, 0.08)
                                border.color: win.accent
                                border.width: 1
                                Text {
                                    id: addT
                                    anchors.centerIn: parent
                                    text: modelData.l
                                    color: win.accent
                                    font.family: Services.Fonts.family
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.aether.beginAdd(win.aether.groupTheme, modelData.v)
                                }
                            }
                        }

                        // --- explaining what a flat view means ---
                        Text {
                            visible: !win.aether.groupOpen && win.aether.view === "themes"
                                     && win.aether.addTheme === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "grouped by theme — click a card to open it"
                                + "  ·  F2 rename  ·  Del delete"
                            color: Services.Colors.textMuted
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                        }
                        Text {
                            visible: win.aether.view === "local" && win.aether.addTheme === ""
                            anchors.verticalCenter: parent.verticalCenter
                            text: "standalone wallpapers in ~/Wallpapers "
                                + "(theme wallpapers live under Themes)"
                            color: Services.Colors.textMuted
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                        }

                        // --- wallhaven filters ---
                        Repeater {
                            model: win.aether.view === "wallhaven" ? win.aether.sortings : []
                            delegate: Rectangle {
                                required property var modelData
                                width: sortT.implicitWidth + 18
                                height: 28
                                radius: 7
                                readonly property bool on: win.aether.whSorting === modelData.id
                                color: on ? Services.Colors.accent
                                    : Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                              Services.Colors.text.b, 0.08)
                                border.color: on ? Services.Colors.accent : Services.Colors.low
                                border.width: 1
                                Text {
                                    id: sortT
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: on ? Services.Colors.background
                                              : Services.Colors.textMuted
                                    font.family: Services.Fonts.family
                                    font.pixelSize: 12
                                    font.bold: on
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.aether.setSorting(modelData.id)
                                }
                            }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        visible: win.aether.view === "wallhaven" && win.aether.whLastPage > 1
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: win.aether.whSearching ? "searching ..."
                                : "page " + win.aether.whPage + " / " + win.aether.whLastPage
                            color: Services.Colors.textMuted
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                        }
                        Repeater {
                            model: ["◀", "▶"]
                            delegate: Rectangle {
                                required property var modelData
                                width: 28; height: 28; radius: 7
                                color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                               Services.Colors.text.b, 0.08)
                                border.color: Services.Colors.low
                                border.width: 1
                                Text {
                                    font.family: Services.Fonts.family
                                    anchors.centerIn: parent
                                    text: modelData
                                    color: Services.Colors.textMuted
                                    font.pixelSize: 12
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: win.aether.whPageTo(
                                        win.aether.whPage + (modelData === "▶" ? 1 : -1))
                                }
                            }
                        }
                    }

                    // --- rename / delete the selected theme ---------------
                    // Sits opposite the wallhaven pager, which is only ever
                    // visible in the wallhaven view, so the two never collide.
                    Row {
                        id: themeActions
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 6
                        visible: toolbar.showThemeActions

                        Rectangle {
                            visible: win.renaming
                            width: renameI.width + 20
                            height: 28
                            radius: 7
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                           Services.Colors.text.b, 0.10)
                            border.color: win.accent
                            border.width: 1

                            TextInput {
                                id: renameI
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.verticalCenter: parent.verticalCenter
                                width: 200
                                color: Services.Colors.text
                                font.family: Services.Fonts.family
                                font.pixelSize: 12
                                focus: win.renaming
                                text: win.renameDraft
                                onTextChanged:
                                    if (win.renameDraft !== text) win.renameDraft = text
                                onFocusChanged: if (focus) {
                                    forceActiveFocus()
                                    cursorPosition = length
                                }
                                // Clicking away abandons the rename rather than
                                // leaving a field visible that no longer has keys.
                                onActiveFocusChanged:
                                    if (!activeFocus && win.renaming) win.cancelRename()
                                Keys.onReturnPressed: (e) => {
                                    e.accepted = true; win.commitRename()
                                }
                                Keys.onEnterPressed: (e) => {
                                    e.accepted = true; win.commitRename()
                                }
                                Keys.onEscapePressed: (e) => {
                                    e.accepted = true; win.cancelRename()
                                }
                            }
                            Text {
                                visible: win.renameDraft === ""
                                anchors.left: renameI.left
                                anchors.verticalCenter: renameI.verticalCenter
                                text: "new theme name"
                                color: Services.Colors.textMuted
                                font.family: Services.Fonts.family
                                font.pixelSize: 12
                            }
                        }

                        Rectangle {
                            visible: win.renaming
                            width: saveT.implicitWidth + 20
                            height: 28
                            radius: 7
                            color: win.accent
                            border.color: win.accent
                            border.width: 1
                            Text {
                                id: saveT
                                anchors.centerIn: parent
                                text: "Save"
                                color: Services.Colors.background
                                font.family: Services.Fonts.family
                                font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.commitRename()
                            }
                        }

                        Rectangle {
                            visible: win.renaming
                            width: 44
                            height: 28
                            radius: 7
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                           Services.Colors.text.b, 0.08)
                            border.color: Services.Colors.low
                            border.width: 1
                            Text {
                                anchors.centerIn: parent
                                text: "Esc"
                                color: Services.Colors.textMuted
                                font.family: Services.Fonts.family
                                font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.cancelRename()
                            }
                        }

                        Rectangle {
                            visible: !win.renaming
                            width: renT.implicitWidth + 20
                            height: 28
                            radius: 7
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                           Services.Colors.text.b, 0.08)
                            border.color: Services.Colors.low
                            border.width: 1
                            Text {
                                id: renT
                                anchors.centerIn: parent
                                text: "Rename"
                                color: Services.Colors.textMuted
                                font.family: Services.Fonts.family
                                font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.beginRename()
                            }
                        }

                        Rectangle {
                            id: deleteBtn
                            readonly property bool armed: win.confirmDelete !== ""
                            visible: !win.renaming
                            width: delT.implicitWidth + 20
                            height: 28
                            radius: 7
                            color: deleteBtn.armed ? Services.Colors.critical
                                : Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                          Services.Colors.text.b, 0.08)
                            border.color: deleteBtn.armed
                                ? Services.Colors.critical : Services.Colors.low
                            border.width: 1
                            Text {
                                id: delT
                                anchors.centerIn: parent
                                // Second press confirms, and the label spells out
                                // which theme it is — it is never a blind click.
                                text: deleteBtn.armed
                                    ? "delete \u201c" + win.confirmDelete + "\u201d?"
                                    : "Delete"
                                color: deleteBtn.armed
                                    ? Services.Colors.background : Services.Colors.textMuted
                                font.family: Services.Fonts.family
                                font.pixelSize: 12
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: win.armDelete()
                            }
                        }
                    }
                }

                Rectangle {
                    id: line2
                    anchors.top: toolbar.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: win.hairline
                    opacity: 0.3
                    visible: toolbar.visible
                }

                // ---------- body ----------
                Item {
                    id: body
                    anchors.top: line2.visible ? line2.bottom : line1.bottom
                    anchors.bottom: line3.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16

                    AetherPalettePanel {
                        id: palettePanel
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: parent.left
                        width: 300
                    }

                    Rectangle {
                        id: vline
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: palettePanel.right
                        anchors.leftMargin: 14
                        width: 1
                        color: win.hairline
                        opacity: 0.35
                    }

                    AetherGrid {
                        id: grid
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.left: vline.right
                        anchors.right: parent.right
                        anchors.leftMargin: 14
                        emptyHint: {
                            const aether = win.aether
                            if (aether.view === "wallhaven")
                                return "no wallhaven results for \u201c" + aether.filter + "\u201d"
                            if (aether.groupOpen)
                                return aether.groupTheme + " has no wallpapers"
                            if (aether.view === "local")
                                return "no standalone wallpapers in ~/Wallpapers"
                            return "no themes with a backgrounds/ folder"
                        }
                        loadingHint: "scanning ..."
                    }
                }

                Rectangle {
                    id: line3
                    anchors.bottom: footer.top
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: 1
                    color: win.hairline
                    opacity: 0.45
                }

                // ---------- footer ----------
                Item {
                    id: footer
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.margins: 16
                    height: 44

                    Text {
                        id: statusT
                        anchors.left: parent.left
                        anchors.right: buttons.left
                        anchors.rightMargin: 16
                        anchors.verticalCenter: parent.verticalCenter
                        verticalAlignment: Text.AlignVCenter
                        text: {
                            const aether = win.aether
                            if (aether.notice) return aether.notice
                            if (aether.statusMsg) return aether.statusMsg
                            if (aether.whSearching) return "searching wallhaven ..."
                            if (aether.extracting) return "extracting palette ..."
                            if (aether.adjusting) return "adjusting palette ..."
                            if (aether.applying) return "working ..."
                            const n = aether.viewModel.length
                            if (!n) return "nothing selected"
                            const it = aether.viewModel[aether.currentIndex]
                            let s = aether.view
                            if (aether.groupOpen) s += " / " + aether.groupTheme
                            s += "  ·  " + (aether.currentIndex + 1) + "/" + n
                            if (it && it.kind === "wallpaper") s += "  ·  " + it.title
                            if (aether.extractMode) s += "  ·  " + aether.extractMode
                            if (aether.lightMode) s += " · light"
                            return s
                        }
                        color: Services.Colors.textMuted
                        font.family: Services.Fonts.family
                        font.pixelSize: 12
                        elide: Text.ElideRight
                    }

                    Row {
                        id: buttons
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Repeater {
                            model: {
                                const aether = win.aether
                                if (aether.addTheme !== "") {
                                    return [{ l: "Cancel", primary: false, act: "cancel" },
                                            { l: "Add to " + aether.addTheme, primary: true, act: "add" }]
                                }
                                return [
                                    { l: "Create",          primary: false, act: "save" },
                                    { l: "Create + apply",  primary: true,  act: "apply" }
                                ]
                            }
                            delegate: Rectangle {
                                required property var modelData
                                width: btnT.implicitWidth + 34
                                height: 40
                                radius: 10
                                readonly property bool enabled_: {
                                    const aether = win.aether
                                    if (modelData.act === "cancel") return true
                                    if (modelData.act === "add")
                                        return aether.selectedWallpaper() !== null && !aether.busy
                                    return aether.canCreate
                                }
                                color: !enabled_ ? Qt.rgba(Services.Colors.text.r,
                                                           Services.Colors.text.g,
                                                           Services.Colors.text.b, 0.06)
                                    : modelData.primary ? Services.Colors.accent
                                    : Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                              Services.Colors.text.b, 0.10)
                                border.color: modelData.primary ? Services.Colors.accent
                                                                 : Services.Colors.low
                                border.width: 1
                                opacity: enabled_ ? 1 : 0.55
                                Text {
                                    id: btnT
                                    anchors.centerIn: parent
                                    text: modelData.l
                                    color: modelData.primary && parent.enabled_
                                        ? Services.Colors.background : Services.Colors.text
                                    font.family: Services.Fonts.family
                                    font.pixelSize: 13
                                    font.bold: modelData.primary
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: enabled_ ? Qt.PointingHandCursor
                                                          : Qt.ArrowCursor
                                    onClicked: {
                                        if (!enabled_) return
                                        if (modelData.act === "cancel") win.aether.goBack()
                                        else if (modelData.act === "add") win.aether.addToTheme()
                                        else win.aether.create(modelData.act === "apply")
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
