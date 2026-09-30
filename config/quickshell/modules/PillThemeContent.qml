import Quickshell
import Quickshell.Io
import QtQuick
import "../services" as Services

// M3 Expressive CENTER-ALIGNED HERO carousel
// (https://m3.material.io/components/carousel/guidelines): one large
// 16:9 hero card (the selected theme, uncropped screen shot) dead-center,
// every other theme reduced to a small VERTICAL rectangle (the M3 "small
// item" —40-56dp wide portrait) flanking it. The container fits exactly
// hero + two smalls inside the spec's16dp side /8dp top-bottom pads, so
// the pill stays narrow while the thumbnail you actually look at grows.
//
// Motion (don't forget the animations): the row x-binding springs the
// strip sideways on selection change while the outgoing hero morphs down
// into a vertical rectangle and the incoming small grows into the hero —
// "items change size as they move through the carousel". Cards, slots and
// the row all share the spatial spring; labels cross-fade without shifting
// the column; entrance keeps the M3 stagger. Tier sizes: Services.Themes.geom.
//
// Replaces the multi-browse (L/M/S) pass: only two tiers now, and the
// row lives inside a clipper inset by the pads so ±2 items stay hidden.
Item {
    id: root
    property bool active: false
    anchors.fill: parent
    opacity: active ? 1 : 0
    visible: active || opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

    readonly property var geom: Services.Themes.geom

    // label sits in a reserved zone under the cards; cards center on the
    // line above it so the pill never reflows when the hero changes
    readonly property real labelZone: 20    //16 text +4 gap

    focus: root.active
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            // first Escape drops the search, second closes the picker
            if (Services.Themes.query !== "") {
                Services.Themes.query = ""
            } else {
                Services.Themes.closePicker()
            }
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            Services.Themes.moveSelection(1)
            event.accepted = true
        } else if (event.key === Qt.Key_Left) {
            Services.Themes.moveSelection(-1)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            Services.Themes.applySelected()
            event.accepted = true
        } else if (event.key === Qt.Key_Backspace) {
            Services.Themes.query = Services.Themes.query.slice(0, -1)
            event.accepted = true
        } else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32) {
            // hidden search: any printable key starts filtering — no
            // input to click, the pill above fades in as you type
            Services.Themes.query += event.text
            event.accepted = true
        }
    }

    // two tiers only: selected → hero, everything else → vertical rect
    function tierW(i) {
        return i === Services.Themes.selectedIndex ? geom.hw : geom.sw
    }
    function tierH(i) {
        return i === Services.Themes.selectedIndex ? geom.hh : geom.sh
    }
    readonly property var widths: Services.Themes.visibleThemes.map((t, i) => tierW(i))
    readonly property real rowWidth: widths.reduce((a, b) => a + b, 0)
        + geom.spacing * Math.max(0, widths.length - 1)
    // width before the hero, including the gap in front of it
    readonly property real preWidth: widths.slice(0, Services.Themes.selectedIndex)
        .reduce((a, b) => a + b, 0) + geom.spacing * Services.Themes.selectedIndex

    // clipper inset by the spec's pads: the row spans ALL themes but only
    // hero ± one small ever shows — ±2 starts right past the edge
    Item {
        id: clip
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.geom.padX
        anchors.rightMargin: root.geom.padX
        anchors.topMargin: root.geom.padY
        anchors.bottomMargin: root.geom.padY
        clip: true

        Row {
            id: row
            height: parent.height
            spacing: geom.spacing

            // center the hero, clamped flush at the list start/end instead
            // of floating with dead space at the extremes
            x: Math.max(clip.width - root.rowWidth,
                        Math.min(0, (clip.width - root.geom.hw) / 2 - root.preWidth))
            Behavior on x { SpringAnimation { spring: Services.Motion.bounceSpring; damping: Services.Motion.bounceDamping } }

            Repeater {
                model: Services.Themes.visibleThemes

                delegate: Item {
                    id: slot
                    width: root.widths[index]
                    height: root.height
                    // same spring as the card itself: the row glides while
                    // cards morph, instead of snapping slots first
                    Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                    readonly property bool focal: index === Services.Themes.selectedIndex

                    // M3 staggered entrance: each card waits its turn, then eases in
                    opacity: root.active ? 1 : 0
                    Behavior on opacity {
                        SequentialAnimation {
                            PauseAnimation { duration: Services.Motion.staggerDelay(index) }
                            NumberAnimation {
                                duration: Services.Motion.emphasizedEnter
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Services.Motion.emphasizedDecelerate
                            }
                        }
                    }

                    Column {
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                        // cards center on the line above the label zone
                        anchors.verticalCenterOffset: -root.labelZone / 2
                        spacing: 4

                        Rectangle {
                            id: swatch

                            // size IS the selection signal (M3 hero vs small
                            // vertical rect); no borders anywhere
                            width: root.tierW(index)
                            height: root.tierH(index)
                            radius: root.geom.radius
                            clip: true
                            anchors.horizontalCenter: parent.horizontalCenter

                            property var themeData: ({})

                            // the hero<->rect morph: portrait crop on the
                            // smalls (cover scales by height, slicing the
                            // screen shot down its middle), full frame on
                            // the hero — re-crops continuously while the
                            // springs resize the box
                            Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
                            Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                            // Card art, in order:
                            //   1. the per-theme screenshot from
                            //      scripts/generate-previews.sh (scratch workspace
                            //      with neovim + btop open) — only the omarchy
                            //      themes have one;
                            //   2. the theme's OWN wallpaper, for themes that have
                            //      never been shot (everything aether creates), so
                            //      the card shows the theme rather than colour bars;
                            //   3. the four palette stripes below, for a theme with
                            //      no image at all.
                            Image {
                                id: preview
                                anchors.fill: parent
                                source: {
                                    const shot = Services.Themes.previewOf[modelData]
                                    if (shot) return "file://" + shot
                                    const wall = Services.Themes.wallpaperOf[modelData]
                                    return wall ? "file://" + wall : ""
                                }
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                // wallpapers are multi-MB originals; decode at
                                // thumbnail size instead of full resolution
                                sourceSize.width: 640
                                visible: status === Image.Ready
                            }

                            // four palette stripes from THIS theme's colors.json —
                            // primary / container / text / background
                            Row {
                                id: stripes
                                anchors.fill: parent
                                visible: preview.status !== Image.Ready

                                Repeater {
                                    model: ["primary", "secondary_container", "on_background", "background"]

                                    Rectangle {
                                        width: stripes.width / 4
                                        height: stripes.height
                                        color: {
                                            const md3 = swatch.themeData.md3
                                            return (md3 && md3[modelData]) || "#888888"
                                        }
                                    }
                                }
                            }

                            FileView {
                                path: Quickshell.env("HOME") + "/.config/themes/" + modelData + "/quickshell/colors.json"
                                onLoaded: {
                                    try {
                                        swatch.themeData = JSON.parse(text())
                                    } catch (e) {
                                        console.log("PillThemeContent: failed to parse", modelData, e)
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    Services.Themes.selectedIndex = index
                                    Services.Themes.apply(modelData)
                                }
                            }
                        }

                        // name under the hero only — stays in the Column at
                        // opacity0 for every card so the column height is
                        // constant and the cards never jump when the hero
                        // moves; it cross-fades between neighbours instead
                        Text {
                            font.family: Services.Fonts.family
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData
                            color: Services.Colors.text
                            font.pixelSize: root.geom.font
                            elide: Text.ElideRight
                            width: implicitWidth > root.geom.hw ? root.geom.hw : implicitWidth
                            opacity: slot.focal ? 1 : 0
                            Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: Services.Themes
        function onOpenChanged() {
            if (root.active) {
                // row x-binding already lands the hero in place —
                // just hand over the keyboard
                root.forceActiveFocus()
            }
        }
    }

    // hidden search — nothing to click: open the picker and start typing
    // (root keeps focus) and this pill fades in top-right, filtering
    // the row. Same feel as the app launcher's type-to-search.
    Rectangle {
        id: searchPill
        anchors.top: parent.top
        anchors.right: parent.right
        height: 26
        width: searchRow.implicitWidth + 28
        radius: 13
        color: Services.Colors.surface
        opacity: Services.Themes.query.length > 0 ? 1 : 0
        visible: opacity > 0
        z: 1
        Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

        Row {
            id: searchRow
            anchors.centerIn: parent
            spacing: 7

            Text {
                font.family: Services.Fonts.family
                text: "󰍉"
                color: Services.Colors.accent
                font.pixelSize: 13
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                font.family: Services.Fonts.family
                text: Services.Themes.query
                color: Services.Colors.text
                font.pixelSize: 12
                anchors.verticalCenter: parent.verticalCenter
            }
            Text {
                font.family: Services.Fonts.family
                text: Services.Themes.visibleThemes.length
                color: Services.Colors.textMuted
                font.pixelSize: 11
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
