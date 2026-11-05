import QtQuick
import QtQuick.Controls   // ToolTip attached property on the name + hero
import Quickshell
import Quickshell.Io
import "../services" as Services

// Carousel control — the `carousel` row type. The macOS Wallpaper-pane
// layout: ONE large click-to-apply preview of the current selection
// (accent ring, the whole point of the card), the name under it, and a
// wrapped strip of neighbour thumbnails below — click a thumb to move
// the selection, click the hero to APPLY it (a full switch runs the
// system retint / wallpaper commit, so it stays deliberate — same
// apply-through-Themes/Wallpapers contract as the old hero strip, just
// with five visible neighbours instead of two).
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
    // what the name line shows: themes by name, wallpapers by file name
    // (the full path stays on the hover tooltip — it's informative, but
    // it drowned the card when set inline)
    readonly property string displayName: {
        if (selName === "") return ""
        if (themes) return selName
        const i = selName.lastIndexOf("/")
        return i >= 0 ? selName.slice(i + 1) : selName
    }

    // card layout — SettingsWindow sizes rows as 64 + extraHeight; the
    // column height already includes the 50px label-block head, so the
    // row grows to fit the card exactly (loader anchors us both sides)
    height: col.implicitHeight
    readonly property real extraHeight: col.implicitHeight - 64

    readonly property real heroH: 148
    readonly property real thumbH: 58
    readonly property int thumbCount: Math.min(5, Math.max(1, list.length))

    function step(delta) {
        // thumbs only MOVE the selection — no theme work per click: a
        // full switch runs ~0.7s of python/gsettings/foot retint and
        // stacking that on every hop felt slow. Click the hero to apply.
        if (list.length < 2) return
        if (themes) Services.Themes.moveSelection(delta)
        else Services.Wallpapers.moveSelection(delta)
    }
    function applyCurrent() {
        if (list.length === 0) return
        if (themes) Services.Themes.apply(list[sel])
        else Services.Wallpapers.apply(list[sel])
    }

    // the hero's own art — thrown out and settled back on every step,
    // source swapped while invisible (same M3 move the old strip used)
    property int heroDir: 1
    property int heroLastSel: -1
    onSelChanged: {
        if (heroLastSel < 0) { heroLastSel = sel; return }
        let d = sel - heroLastSel
        const n = Math.max(1, list.length)
        if (d > n / 2) d -= n
        else if (d < -n / 2) d += n
        heroDir = d >= 0 ? 1 : -1
        heroLastSel = sel
        heroSwap.restart()
    }

    // slot art: theme screenshot (or, for themes that have never been
    // shot, the theme's own wallpaper), palette stripes as the last
    // resort; wallpaper photo for the wallpaper row
    function artOf(name) {
        if (name === "") return ""
        if (!root.themes) return "file://" + name
        const shot = Services.Themes.previewOf[name]
        if (shot) return "file://" + shot
        const wall = Services.Themes.wallpaperOf[name]
        return wall ? "file://" + wall : ""
    }

    Column {
        id: col
        width: parent.width
        spacing: 10

        Item { width: 1; height: 50 }   // clears the row's label block

        Rectangle {
            width: col.width
            height: cardCol.implicitHeight + 28
            radius: 16
            color: Services.Colors.surface
            border.color: Services.Colors.low
            border.width: 1

            Column {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 14
                spacing: 10

                // ——— the big preview ——— click to apply
                Rectangle {
                    id: hero
                    width: cardCol.width
                    height: root.heroH
                    radius: 12
                    clip: true
                    color: Services.Colors.surfaceAlt
                    border.color: Services.Colors.accent
                    border.width: 2
                    property real dx: 0
                    property string shownName: root.selName
                    x: dx

                    // theme palette for the stripe fallback (ids resolve
                    // through scope; the stripe delegates reference this
                    // as hero.themeData)
                    property var themeData: ({})

                    Image {
                        id: heroPic
                        anchors.fill: parent
                        source: root.artOf(hero.shownName)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        sourceSize.width: 800
                        visible: status === Image.Ready
                    }
                    FileView {
                        printErrors: false
                        path: root.themes && hero.shownName !== ""
                            ? Quickshell.env("HOME") + "/.config/themes/" + hero.shownName + "/quickshell/colors.json"
                            : ""
                        onLoaded: {
                            try { hero.themeData = JSON.parse(text()) } catch (e) {}
                        }
                    }
                    Row {
                        anchors.fill: parent
                        visible: root.themes && heroPic.status !== Image.Ready
                        Repeater {
                            model: ["primary", "secondary_container", "on_background", "background"]
                            Rectangle {
                                width: hero.width / 4
                                height: hero.height
                                color: {
                                    const md3 = hero.themeData.md3
                                    return (md3 && md3[modelData]) || Services.Colors.surfaceAlt
                                }
                            }
                        }
                    }

                    SequentialAnimation {
                        id: heroSwap
                        ParallelAnimation {
                            NumberAnimation {
                                target: hero; property: "dx"
                                to: -root.heroDir * 18
                                duration: Services.Motion.short1
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Services.Motion.emphasizedAccelerate
                            }
                            NumberAnimation {
                                target: hero; property: "opacity"
                                to: 0
                                duration: Services.Motion.short1
                                easing.type: Easing.BezierSpline
                                easing.bezierCurve: Services.Motion.emphasizedAccelerate
                            }
                        }
                        ScriptAction { script: hero.shownName = root.selName }
                        PropertyAction {
                            target: hero; property: "dx"
                            value: root.heroDir * 18
                        }
                        ParallelAnimation {
                            SpringAnimation {
                                target: hero; property: "dx"
                                to: 0
                                spring: Services.Motion.bounceSpring
                                damping: Services.Motion.bounceDamping
                            }
                            NumberAnimation {
                                target: hero; property: "opacity"
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
                        onClicked: root.applyCurrent()
                    }
                    ToolTip.visible: heroHover.containsMouse && root.selName !== ""
                    ToolTip.delay: 400
                    ToolTip.text: "Apply " + root.selName
                    HoverHandler { id: heroHover }
                }

                // ——— name + hint ——— the roll-up swap on every step
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 6

                    Text {
                        id: nameText
                        font.family: Services.Fonts.family
                        text: root.displayName
                        font.pixelSize: 13
                        font.bold: true
                        color: Services.Colors.text
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, cardCol.width - 160)
                        Accessible.role: Accessible.StaticText
                        Accessible.name: "Selected: " + root.selName

                        HoverHandler { id: nameHover }
                        // truncated names ("aether-defa…") get the full
                        // string on hover instead of a filesystem trip
                        ToolTip.visible: !!nameHover.containsMouse && !!nameText.truncated
                        ToolTip.delay: 400
                        ToolTip.text: root.selName

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
                        // roll offset rides the row's baseline
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.verticalCenterOffset: rollY
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Services.Fonts.family
                        text: "·  click the preview to apply"
                        font.pixelSize: 10
                        color: Services.Colors.textMuted
                        visible: root.list.length > 0
                    }
                }

                // ——— thumbnail strip ——— wrapped window of neighbours,
                // the current one accent-ringed; click = move selection
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8

                    Repeater {
                        model: root.list.length > 0 ? root.thumbCount : 0

                        delegate: Item {
                            id: thumb
                            required property int index
                            readonly property int off: index - Math.floor(root.thumbCount / 2)
                            readonly property int wrap: (root.sel + off + root.list.length)
                                % Math.max(1, root.list.length)
                            readonly property string name: (wrap >= 0 && wrap < root.list.length)
                                ? root.list[wrap] : ""   // bounds-guarded like selName
                            readonly property bool current: off === 0

                            width: (cardCol.width - 28 - (root.thumbCount - 1) * 8) / root.thumbCount
                            height: root.thumbH

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                clip: true
                                color: Services.Colors.surfaceAlt
                                border.color: thumb.current ? Services.Colors.accent
                                                            : Services.Colors.low
                                border.width: thumb.current ? 2 : 1

                                Image {
                                    anchors.fill: parent
                                    source: root.artOf(thumb.name)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    sourceSize.width: 320
                                    visible: status === Image.Ready
                                }
                                // dim the neighbours so the current reads
                                // as the selection (thaws on hover)
                                Rectangle {
                                    anchors.fill: parent
                                    color: Services.Colors.background
                                    opacity: thumb.current ? 0
                                        : (thumbMa.containsMouse ? 0.25 : 0.5)
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: Services.Motion.effectsFast
                                            easing.type: Easing.BezierSpline
                                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                id: thumbMa
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                enabled: !thumb.current && root.list.length > 1
                                onClicked: root.step(thumb.off)
                            }
                        }
                    }
                }
            }
        }
    }
}
