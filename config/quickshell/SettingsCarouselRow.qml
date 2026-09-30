import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Carousel control — the `carousel` row type. Adapts the shell's M3
// center-aligned hero carousel (PillThemeContent / PillWallpaperContent
// in the pill pickers) to the settings renderer as a power-style CARD:
// the delegate's label block (Theme / Wallpaper + hint) sits at the row
// top, a 50px head clears it, then the card shell holds the LARGE
// ‹ small · hero · small › strip with the name beside it. Arrows step
// the selection (preview only — switching runs the whole system retint,
// so it stays click-to-apply via the hero, through Themes.apply /
// Wallpapers.apply).
Item {
    id: root

    property var e: null
    readonly property bool themes: e && e.source === "themes"
    readonly property var list: themes ? Services.Themes.visibleThemes
                                       : Services.Wallpapers.wallpapers
    readonly property int sel: {
        const raw = themes ? Services.Themes.selectedIndex : Services.Wallpapers.selectedIndex
        if (list.length === 0) return 0
        return Math.max(0, Math.min(list.length - 1, raw))
    }
    // bounds-guarded: when a scan() replaces the list, this binding can
    // re-evaluate with the new list while `sel` still holds the old clamp
    // (bindings refresh in dependency order, not atomically) — list[sel]
    // then reads undefined and QML warns on the QString assign
    readonly property string selName: (list.length > 0 && sel < list.length)
                                      ? list[sel] : ""

    // card layout — SettingsWindow sizes rows as 64 + extraHeight; the
    // column height already includes the 50px label-block head, so the
    // row grows to fit the card exactly (loader anchors us both sides)
    height: col.implicitHeight
    readonly property real extraHeight: col.implicitHeight - 64

    // the large hero strip — the title lives in the row's label block
    readonly property real heroW: 210
    readonly property real heroH: 116
    readonly property real smallW: 64
    readonly property real smallH: 116

    function step(delta) {
        // stepping only MOVES the selection — no theme work per arrow:
        // a full switch runs ~0.7s of python/gsettings/foot retint and
        // stacking that on every step felt slow and memory-hungry. Click
        // the hero to apply.
        if (themes) Services.Themes.moveSelection(delta)
        else Services.Wallpapers.moveSelection(delta)
    }
    function applyCurrent() {
        if (list.length === 0) return
        if (themes) Services.Themes.apply(list[sel])
        else Services.Wallpapers.apply(list[sel])
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        Item { width: 1; height: 50 }   // clears the row's label block

        Rectangle {
            width: col.width
            height: stripRow.height + 28
            radius: 16
            color: Services.Colors.surface
            border.color: Services.Colors.low
            border.width: 1

            Row {
                id: stripRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 14
                spacing: 6

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 12
            color: backL.containsMouse ? Services.Colors.surfaceAlt : Services.Colors.surface

            Behavior on color {
                ColorAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }
            Text {
                font.family: Services.Fonts.family
                anchors.centerIn: parent
                text: "‹"
                font.pixelSize: 16
                font.bold: true
                color: Services.Colors.text
            }
            MouseArea {
                id: backL
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.step(-1)
            }
        }

        // three-slot strip: prev · hero · next, wrapped
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: root.smallW * 2 + root.heroW + 12
            height: root.heroH
            clip: true

            Row {
                anchors.centerIn: parent
                spacing: 6

                Repeater {
                    model: root.list.length > 1 ? 3 : (root.list.length === 1 ? 1 : 0)

                    delegate: Item {
                        id: slot
                        readonly property int slotIdx: index      // 0 prev, 1 hero, 2 next
                        readonly property int wrap: (root.sel + slotIdx - 1 + root.list.length) % Math.max(1, root.list.length)
                        readonly property string name: (root.list.length > 0 && wrap >= 0 && wrap < root.list.length)
                            ? root.list[wrap] : ""   // bounds-guarded like selName (stale wrap vs shrunken list)
                        readonly property bool hero: slotIdx === 1 || root.list.length < 3

                        // step direction (+1 = next, contents advance →
                        // throw left) — derived from how the wrap index
                        // moved, normalized across list ends
                        property int dir: 1
                        property int lastWrap: -1
                        property bool ready: false
                        Component.onCompleted: { lastWrap = wrap; ready = true }
                        onWrapChanged: {
                            if (!ready) return
                            let d = wrap - lastWrap
                            const n = Math.max(1, root.list.length)
                            if (d > n / 2) d -= n
                            else if (d < -n / 2) d += n
                            dir = d >= 0 ? 1 : -1
                            lastWrap = wrap
                            // ids resolve through scope, NOT as object
                            // properties — `card.swap` is undefined (only
                            // QObject properties resolve that way) and
                            // silently threw, so the step transition never
                            // actually ran before this fix
                            swap.restart()
                        }

                        width: hero ? root.heroW : root.smallW
                        height: hero ? root.heroH : root.smallH
                        anchors.verticalCenter: parent.verticalCenter

                        Rectangle {
                            id: card
                            anchors.centerIn: parent
                            anchors.horizontalCenterOffset: dx
                            width: parent.width
                            height: parent.height
                            radius: 12
                            clip: true
                            color: Services.Colors.surface
                            border.color: hero ? Services.Colors.accent : Services.Colors.low
                            border.width: hero ? 1 : 0

                            // slide offset for the step transition
                            property real dx: 0
                            // this slot's OWN item — swapped under cover of
                            // the fade so the outgoing art can throw out first
                            property string shownName: name

                            // active theme's palette (colors.json md3) for the
                            // stripe fallback. Referenced as card.themeData:
                            // the stripe Repeater's delegate has its own scope
                            // and cannot see this unqualified (ids still work).
                            property var themeData: ({})
                            // slot art: theme screenshot (or, for themes that
                            // have never been shot, the theme's own wallpaper),
                            // palette stripes as the last resort; wallpaper
                            // photo for the wallpaper row
                            Image {
                                id: pic
                                anchors.fill: parent
                                source: {
                                    if (card.shownName === "") return ""
                                    if (!root.themes) return "file://" + card.shownName
                                    const shot = Services.Themes.previewOf[card.shownName]
                                    if (shot) return "file://" + shot
                                    const wall = Services.Themes.wallpaperOf[card.shownName]
                                    return wall ? "file://" + wall : ""
                                }
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                sourceSize.width: 640
                                visible: status === Image.Ready
                            }
                            FileView {
                                printErrors: false
                                path: root.themes && card.shownName !== ""
                                    ? Quickshell.env("HOME") + "/.config/themes/" + card.shownName + "/quickshell/colors.json"
                                    : ""
                                onLoaded: {
                                    try { card.themeData = JSON.parse(text()) } catch (e) {}
                                }
                            }
                            Row {
                                anchors.fill: parent
                                visible: root.themes && pic.status !== Image.Ready
                                Repeater {
                                    model: ["primary", "secondary_container", "on_background", "background"]
                                    Rectangle {
                                        width: card.width / 4
                                        height: card.height
                                        color: {
                                            const md3 = card.themeData.md3
                                            return (md3 && md3[modelData]) || Services.Colors.surfaceAlt
                                        }
                                    }
                                }
                            }
                            // small slots: dimmer tint so the hero reads as focal
                            Rectangle {
                                anchors.fill: parent
                                color: Services.Colors.background
                                opacity: hero ? 0 : 0.35
                            }

                            // snappy M3 step transition: the outgoing art
                            // throws out in the step direction (fade +
                            // slide), the source swaps while invisible,
                            // the new art settles back in from the other
                            // side — total 200ms
                            SequentialAnimation {
                                id: swap
                                ParallelAnimation {
                                    NumberAnimation {
                                        target: card; property: "dx"
                                        to: -slot.dir * 18
                                        duration: Services.Motion.short1
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Services.Motion.emphasizedAccelerate
                                    }
                                    NumberAnimation {
                                        target: card; property: "opacity"
                                        to: 0
                                        duration: Services.Motion.short1
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Services.Motion.emphasizedAccelerate
                                    }
                                }
                                ScriptAction { script: card.shownName = slot.name }
                                PropertyAction {
                                    target: card; property: "dx"
                                    value: slot.dir * 18
                                }
                                ParallelAnimation {
                                    // the new art settles with a spring —
                                    // overshoots its slot a hair, snaps back
                                    SpringAnimation {
                                        target: card; property: "dx"
                                        to: 0
                                        spring: Services.Motion.bounceSpring
                                        damping: Services.Motion.bounceDamping
                                    }
                                    NumberAnimation {
                                        target: card; property: "opacity"
                                        to: 1
                                        duration: Services.Motion.effects
                                        easing.type: Easing.BezierSpline
                                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                    }
                                }
                            }

                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (hero) root.applyCurrent()
                                    else root.step(slotIdx === 0 ? -1 : 1)
                                }
                            }
                        }
                    }
                }
            }
        }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 12
            color: backR.containsMouse ? Services.Colors.surfaceAlt : Services.Colors.surface

            Behavior on color {
                ColorAnimation {
                    duration: Services.Motion.effectsFast
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Services.Motion.emphasizedDecelerate
                }
            }
            Text {
                font.family: Services.Fonts.family
                anchors.centerIn: parent
                text: "›"
                font.pixelSize: 16
                font.bold: true
                color: Services.Colors.text
            }
            MouseArea {
                id: backR
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.step(1)
            }
        }

        Text {
            font.family: Services.Fonts.family
            id: nameText
            anchors.verticalCenter: parent.verticalCenter
            anchors.verticalCenterOffset: rollY
            width: 96
            text: root.selName
            font.pixelSize: 13
            font.bold: true
            color: Services.Colors.text
            elide: Text.ElideRight

            // roll-up swap on every step — starts below/transparent and
            // settles in with the same emphasized decelerate as the art
            property real rollY: 0
            property bool ready: false
            Component.onCompleted: ready = true
            onTextChanged: if (ready) rollAnim.restart()

            SequentialAnimation {
                id: rollAnim
                ParallelAnimation {
                    PropertyAction { target: nameText; property: "rollY"; value: 10 }
                    PropertyAction { target: nameText; property: "opacity"; value: 0 }
                }
                ParallelAnimation {
                    SpringAnimation {
                        target: nameText; property: "rollY"
                        to: 0
                        spring: Services.Motion.bounceSpring
                        damping: Services.Motion.bounceDamping
                    }
                    NumberAnimation {
                        target: nameText; property: "opacity"
                        to: 1
                        duration: Services.Motion.effects
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Services.Motion.emphasizedDecelerate
                    }
                }
            }
        }
            }
        }
    }
}
