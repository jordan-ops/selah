import QtQuick
import "../services" as Services

// M3 Expressive CENTER-ALIGNED HERO carousel — wallpaper edition, the
// same layout as PillThemeContent: the selected wallpaper is a large
// uncropped hero dead-centre, neighbours reduce to vertical rectangle
// crops, spec pads (16 sides / 8 top-bottom), 8dp gaps, radius 28, and
// the row/slots/cards all share the spatial spring so picking glides —
// the outgoing hero morphs down into a rect while the next grows in.
// Geometry comes from Services.Themes.geom, so one setSize switch (1/2/3)
// scales BOTH pickers together.
//
// Wallpapers.qml does the per-theme-folder work (themeDir from
// currentTheme, automatic rescan on theme change); apply() writes the
// current-wallpaper state file and Background.qml crossfades. The old
// accent border on the selected thumbnail is gone — size IS the
// selection signal now, matching the theme picker.
//
// The old WallpaperPicker.qml rendered an empty grid because it called
// Wallpapers.files / .selected / .setWallpaper(), none of which exist —
// the real API is .wallpapers / .selectedIndex / .apply().
Item {
    id: root
    property bool active: false
    anchors.fill: parent
    opacity: active ? 1 : 0
    visible: active || opacity > 0.01
    Behavior on opacity { NumberAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

    readonly property var geom: Services.Themes.geom
    readonly property real labelZone: 20    // 16 text + 4 gap (shared with theme picker)

    focus: root.active
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            Services.Wallpapers.closePicker()
            event.accepted = true
        } else if (event.key === Qt.Key_Right) {
            Services.Wallpapers.moveSelection(1)
            event.accepted = true
        } else if (event.key === Qt.Key_Left) {
            Services.Wallpapers.moveSelection(-1)
            event.accepted = true
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            Services.Wallpapers.applySelected()
            Services.Wallpapers.closePicker()
            event.accepted = true
        }
    }

    // empty-state note (missing backgrounds folder / scan came back empty)
    Text {
        font.family: Services.Fonts.family
        anchors.centerIn: parent
        visible: Services.Wallpapers.wallpapers.length === 0
        text: "No wallpapers found for this theme"
        color: Services.Colors.text
        opacity: 0.6
        font.pixelSize: 12
        z: 1
    }

    // two tiers only: selected -> hero, everything else -> vertical rect
    function tierW(i) {
        return i === Services.Wallpapers.selectedIndex ? geom.hw : geom.sw
    }
    function tierH(i) {
        return i === Services.Wallpapers.selectedIndex ? geom.hh : geom.sh
    }
    readonly property var widths: Services.Wallpapers.wallpapers.map((t, i) => tierW(i))
    readonly property real rowWidth: widths.reduce((a, b) => a + b, 0)
        + geom.spacing * Math.max(0, widths.length - 1)
    // width before the hero, including the gap in front of it
    readonly property real preWidth: widths.slice(0, Services.Wallpapers.selectedIndex)
        .reduce((a, b) => a + b, 0) + geom.spacing * Services.Wallpapers.selectedIndex

    // clipper inset by the spec's pads: the row spans every wallpaper of
    // the theme but only hero ± one small ever shows — ±2 stays hidden
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

            // centre the hero, clamped flush at the list start/end
            x: Math.max(clip.width - root.rowWidth,
                        Math.min(0, (clip.width - root.geom.hw) / 2 - root.preWidth))
            Behavior on x { SpringAnimation { spring: Services.Motion.bounceSpring; damping: Services.Motion.bounceDamping } }

            Repeater {
                model: Services.Wallpapers.wallpapers

                delegate: Item {
                    id: slot
                    width: root.widths[index]
                    height: root.height
                    // same spring as the card: the row glides while cards
                    // morph instead of snapping slots first
                    Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                    readonly property bool focal: index === Services.Wallpapers.selectedIndex

                    // M3 staggered entrance: thumbnails cascade in on open
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
                        // cards centre on the line above the label zone
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
                            color: "#1a1a1a"   // loading plate behind big photos

                            // the hero<->rect morph: portrait slice on the
                            // smalls (cover scales by height, cropping the
                            // photo down its middle), full frame on the hero
                            Behavior on width { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }
                            Behavior on height { SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping } }

                            Image {
                                anchors.fill: parent
                                source: "file://" + modelData
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true   // keeps the strip from freezing while loading
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    Services.Wallpapers.selectedIndex = index
                                    Services.Wallpapers.apply(modelData)
                                    Services.Wallpapers.closePicker()
                                }
                            }
                        }

                        // file name under the hero only — stays in the
                        // Column at opacity 0 for every card so the column
                        // height is constant and cards never jump when the
                        // hero moves; it cross-fades between neighbours
                        Text {
                            font.family: Services.Fonts.family
                            anchors.horizontalCenter: parent.horizontalCenter
                            text: modelData.split("/").pop().replace(/\.[^.]+$/, "")
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
        target: Services.Wallpapers
        function onOpenChanged() {
            if (root.active) {
                // row x-binding already lands the hero in place —
                // just hand over the keyboard
                root.forceActiveFocus()
            }
        }
    }
}
