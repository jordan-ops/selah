import QtQuick
import "../modules"
import "../services" as Services

// The pill's RESTING content — compact capsule (restStyle "compact"),
// the segmented full row, and the tray chevron chip — extracted from
// Bar.qml in the Phase B split. The pill owns all state; this file only
// draws it. It reads pill.mode / pill.trayTouch / pill.compactAtRest /
// pill.traySlot / pill.trayOpen through the `pill` property, and the
// pill's width math (traySlot / compactBarWidth / fullBarWidth) plus the
// tray popup's chevron-centering read the measured children back through
// the aliases below.
Item {
    id: normalContent
    property var pill: null
    property alias trayChip: trayChip
    property alias compactRow: compactRow
    property alias leftRow: leftRow
    property alias rightGroup: rightGroup
    property alias workspacesItem: workspacesItem
    anchors.fill: parent
    opacity: pill.mode === "rest" ? 1 : 0
    // opacity alone does NOT gate input in Qt Quick -- an
    // invisible item still takes clicks. The `|| opacity > 0.01`
    // tail keeps the fade-out animating; the condition half is
    // what makes it live on frame 1 (search fields need focus).
    visible: (pill.mode === "rest") || opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

    // ----- compact capsule (restStyle "compact", collapsed) -----
    // time · workspace dots · battery % — the pill hugs this row
    // (30px tall) and springs open to the full segmented row on
    // hover/click (grace timer lives with the pill props).
    Row {
        id: compactRow
        anchors.centerIn: parent
        // the tray slot eats the pill's right side — pull the
        // capsule row left by half of it so its left/right
        // breathing room stays symmetric (16/16 around row+slot)
        anchors.horizontalCenterOffset: -pill.traySlot / 2
        spacing: 14
        // crossfade instead of pop: the capsule row and the
        // segmented row swap places while the pill springs,
        // so both sides fade through each other
        opacity: pill.compactAtRest() ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Services.Motion.effects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.emphasizedDecelerate
            }
        }

        MediaVisualiser {}

        Clock {}

        Workspaces {
            anchors.verticalCenter: parent.verticalCenter
        }

        // iOS battery + wifi, split out of the old combo ring.
        // Clicking either opens the control centre directly —
        // the pill's own hoverArea would otherwise just pin the
        // expanded row under the pointer (which is what a click
        // on empty capsule still does).
        Item {
            id: compactStatus
            anchors.verticalCenter: parent.verticalCenter
            width: compactStatusRow.width
            height: compactStatusRow.height

            Row {
                id: compactStatusRow
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                BatteryIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    // sits on the pill, not on a surface chip
                    background: Services.Colors.panel
                }

                WifiIcon {
                    anchors.verticalCenter: parent.verticalCenter
                }
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Services.ControlCenter.toggle()
            }
        }
    }

    // ----- full segmented row: left chip | dots | right chips -----
    // restStyle "wide" shows this always; "compact" shows it while
    // hover-expanded. The surface chip around clock · date is half
    // the segmented-pill identity — recording/updates live out in
    // the activity chips that slide from the pill's right edge;
    // media moved back INSIDE as MediaVisualiser (its chip +
    // detached popup are gone).
    Rectangle {
        id: leftChip
        anchors.left: parent.left
        anchors.leftMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 26
        width: leftRow.width + 24
        radius: height / 2
        color: Services.Colors.surface
        opacity: !pill.compactAtRest() ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Services.Motion.effects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.emphasizedDecelerate
            }
        }

        Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
        Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

        Row {
            id: leftRow
            anchors.centerIn: parent
            spacing: 10

            MediaVisualiser {}

            Clock {
                id: clockItem
            }

            // date joins the clock once the row is wide enough for it
            Text {
                font.family: Services.Fonts.family
                anchors.verticalCenter: parent.verticalCenter
                text: Services.Time.date
                color: Services.Colors.textMuted
                font.pixelSize: 12
            }
        }
    }

    // workspaces sit dead center of the bar, independent of how wide
    // the left/right groups are — like Waybar's modules-center array
    Workspaces {
        id: workspacesItem
        anchors.centerIn: parent
        opacity: !pill.compactAtRest() ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Services.Motion.effects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.emphasizedDecelerate
            }
        }
    }

    Row{
        id: rightGroup
        anchors.right:parent.right
        // + traySlot: the tray chip sits to the right of this
        // row (inside the pill), so the row shifts left to
        // leave the slot open
        anchors.rightMargin:12 + pill.traySlot
        anchors.verticalCenter:parent.verticalCenter
        spacing: 10
        // crossfade with the compact capsule — see compactRow
        opacity: !pill.compactAtRest() ? 1 : 0
        visible: opacity > 0.01

        Behavior on opacity {
            NumberAnimation {
                duration: Services.Motion.effects
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.emphasizedDecelerate
            }
        }

        // recording + updates indicators moved out to the
        // activity chips that slide from the pill's right edge —
        // they must be reachable from the compact capsule too,
        // not just from this expanded row.


        
        // clipboard history — same self-contained glyph+MouseArea
        // shape as the ⏻ below; opens the pill's clipboard mode
        // (\uD838\uDCEA = U+F0EA, FA clipboard, covered by Mononoki)
        Text {
            font.family: Services.Fonts.family
            text: "\uD838\uDCEA"
            color: Services.Colors.text
            font.pixelSize: 14
            font.bold: true
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: Services.Clipboard.toggle()
            }
        }

        // battery/wifi/power grouped into one pill — clicking anywhere
        // in it opens the control center. the power icon keeps its own
        // MouseArea on top, so clicking IT still opens the power menu
        // directly (it used to be commented out = dead control, not anymore)
        Rectangle {
            id: statusGroup
            width: statusRow.width + 20
            height: 26
            radius: 13
            color: Services.Colors.surface
            anchors.verticalCenter: parent.verticalCenter

            MouseArea {
                anchors.fill: parent
                onClicked: Services.ControlCenter.toggle()
            }

            Row {
                id: statusRow
                anchors.centerIn: parent
                spacing: 10

                // iOS battery + wifi glyph, split apart (the
                // ring used to carry both): the % lives inside
                // the battery when bar.batteryText is on, and
                // the network is icon-only. Clicking the chip —
                // or the ⏻ on top of it — still opens the CC.
                BatteryIcon {
                    anchors.verticalCenter: parent.verticalCenter
                }

                WifiIcon {
                    anchors.verticalCenter: parent.verticalCenter
                }

                Text {
                    font.family: Services.Fonts.family
                    text: "⏻"
                    color: Services.Colors.text
                    font.pixelSize: 14
                    font.bold: true
                    anchors.verticalCenter: parent.verticalCenter

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.PowerMenu.open = !Services.PowerMenu.open
                    }
                }
            }
        }
    }

    // ---------------- system tray: the arrow ----------------
    // The chip no longer holds the icons — it is just the trigger.
    // pill.traySlot still carves its room out of both rest widths
    // (it reads trayChip.width), so the pill's width math is
    // unchanged in shape; the slot is just narrower now that the
    // chip is arrow-sized instead of arrow-plus-icon-row.
    //
    // Position is unchanged: still anchored to the pill's right
    // edge with rightGroup shifted left by traySlot, which puts
    // this immediately after statusGroup (battery · wifi ·
    // power) — the last child of rightGroup.
    Rectangle {
        id: trayChip
        readonly property bool expanded: pill.trayOpen
            // no more `|| !pill.compactAtRest()`: the wide rest
            // row used to keep the icons permanently inline. The
            // tray is hover-driven now, and leaving it inline in
            // one state but popups in the other meant the arrow
            // pointed at nothing whenever the row was open.
            // (hasIcons is gone too — visibility no longer
            // depends on tray contents, see below.)

        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        height: 26
        width: 26
        radius: 13
        color: trayArea.containsMouse || trayChip.expanded
            ? Services.Colors.surfaceAlt : Services.Colors.surface
        // ALWAYS visible. It used to be gated on
        // SystemTray.items.values.length > 0, and this machine has
        // no tray applet installed at all (nm-applet, blueman-applet,
        // etc. are all absent), so the condition was permanently
        // false — the arrow has literally never rendered, in the old
        // inline chip and in this one. Hiding an affordance only
        // because it currently has nothing to reveal also makes the
        // bar's chrome change shape as tray apps come and go, which
        // drags the whole pill layout with it. Now it's constant and
        // the EMPTY state says so instead (trayEmptyHint, below).

        // ColorAnimation, NOT NumberAnimation. NumberAnimation
        // drives a property by reading/writing it as a double, and
        // QColor has no numeric conversion — QVariant::toDouble()
        // on a colour yields 0.0, so the animation ran 0 -> 0 and
        // wrote back 0x000000. That turned this chip pure black
        // instead of surface, and the same bug on trayArrow (below)
        // turned the chevron black too, so both were black-on-black
        // and the arrow looked like a solid black dot. The rest of
        // the config's 51 colour Behaviors all use ColorAnimation;
        // these three were the only ones that didn't.
        Behavior on color {
            ColorAnimation {
                duration: Services.Motion.effectsFast
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Services.Motion.standardCurve
            }
        }

        // Down-chevron, not the old sideways "›". A down-chevron
        // promises content below, which is now true — the popup
        // drops down out of the bar (the bar is the TOP layer, so
        // Meet's upward pop is mirrored). Rotating 180° turns it
        // into the up-chevron that says "already open".
        Text {
            font.family: Services.Fonts.family
            id: trayArrow
            // NOT centerIn. U+2304 hangs ~4px below the centre of
            // its em box (measured on a capture: chip centre y14.5,
            // chevron ink centre y18.5), so centring the Text ITEM
            // left the visible chevron sitting low in the circle.
            // Lifting it 4px fixes the resting state — but rotation
            // spins the item about ITS OWN centre, which mirrors
            // that off-centre ink 4px the OTHER way. So the offset
            // reverses while open: closed lands on 14.5, open lands
            // on 14.5 too. A fixed offset would have centred the
            // rest state and thrown the open one to ~6.5, near the
            // chip's top edge.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: trayChip.expanded ? 4 : -4
            text: "⌄"
            font.pixelSize: 15
            color: trayChip.expanded ? Services.Colors.accent : Services.Colors.text
            rotation: trayChip.expanded ? 180 : 0
            Behavior on rotation { SpringAnimation { spring: Services.Motion.spatialFastSpring; damping: Services.Motion.spatialFastDamping } }
            // ColorAnimation (see the note on the chip above):
            // with NumberAnimation this made the chevron #000000,
            // so it was invisible against the blackened chip.
            // Colour now stays Services.Colors.text — the exact
            // value modules/Clock.qml uses for the clock — and
            // flips to accent only while the tray is open.
            Behavior on color {
                ColorAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.standardCurve
                }
            }
        }

        // Hover (and click, for touch/keyboard users) arms the
        // popup. Hover only OPENS — trayIdle decides when it
        // closes, so travelling down into the popup never makes
        // it disappear underneath the pointer.
        MouseArea {
            id: trayArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) pill.trayTouch()
            onClicked: pill.trayTouch()
        }
    }
}
