import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Swatch grid — the new `swatches` (themes) and `wallpapers` row types.
// Embedded directly in the Appearance page instead of the old actions
// that opened popups: clicking a swatch calls the very functions the
// popups apply through (Services.Themes.apply / Services.Wallpapers.apply),
// so there is one apply path. Theme cells show the per-theme screenshot
// thumbnail, falling back to the theme's own wallpaper (the palette stripes
// only appear for a theme with no image at all), exactly like
// PillThemeContent; wallpaper cells are live thumbnails of the active
// theme's images.
Item {
    id: root

    property var e: null
    readonly property bool themes: e && e.source === "themes"
    readonly property var swatchModel: themes ? Services.Themes.themes
                                               : Services.Wallpapers.wallpapers

    readonly property real cellW: themes ? 104 : 100
    readonly property real cellH: 54

    // delegate row math: label zone ends at y=50, grid starts there,
    // 8px pad below -> row(64 + extra) = 50 + grid + 8  =>  extra = grid - 6
    readonly property real extraHeight: Math.max(0, flow.height - 6)

    width: 500
    height: 30 + extraHeight

    Flow {
        id: flow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 50
        spacing: 8

        Repeater {
            model: root.swatchModel

            delegate: Rectangle {
                readonly property bool selected: root.themes
                    ? modelData === Services.Themes.currentTheme
                    : modelData === Services.Wallpapers.current
                readonly property string thumbName: root.themes ? modelData : ""

                width: root.cellW
                height: root.cellH
                radius: 10
                clip: true
                color: Services.Colors.surface
                border.width: selected ? 2 : 1
                border.color: selected ? Services.Colors.accent : Services.Colors.low

                Image {
                    id: pic
                    anchors.fill: parent
                    anchors.margins: 2
                    // themes: the screenshot generate-previews.sh shot, else the
                    // theme's OWN wallpaper (nothing aether creates has a
                    // screenshot) — the stripes below are the last resort.
                    source: {
                        if (!root.themes) return "file://" + modelData
                        const shot = Services.Themes.previewOf[thumbName]
                        if (shot) return "file://" + shot
                        const wall = Services.Themes.wallpaperOf[thumbName]
                        return wall ? "file://" + wall : ""
                    }
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    sourceSize.width: 640
                    visible: status === Image.Ready
                }

                // theme palette stripes until generate-previews.sh has shot it
                Row {
                    id: stripes
                    anchors.fill: parent
                    anchors.margins: 2
                    visible: root.themes && pic.status !== Image.Ready

                    Repeater {
                        model: ["primary", "secondary_container", "on_background", "background"]
                        Rectangle {
                            width: stripes.width / 4
                            height: stripes.height
                            color: {
                                const md3 = cell.themeData.md3
                                return (md3 && md3[modelData]) || Services.Colors.surfaceAlt
                            }
                        }
                    }
                }
                property var themeData: ({})
                FileView {
                    path: root.themes
                        ? Quickshell.env("HOME") + "/.config/themes/" + thumbName + "/quickshell/colors.json"
                        : ""
                    printErrors: false
                    onLoaded: {
                        try { cell.themeData = JSON.parse(text()) } catch (e) {}
                    }
                }

                Text {
                    font.family: Services.Fonts.family
                    visible: !root.themes && pic.status !== Image.Ready
                    anchors.centerIn: parent
                    text: modelData.split("/").pop()
                    font.pixelSize: 9
                    color: Services.Colors.textMuted
                    elide: Text.ElideRight
                    width: parent.width - 8
                    horizontalAlignment: Text.AlignHCenter
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (root.themes) {
                            Services.Themes.selectedIndex = index
                            Services.Themes.apply(modelData)
                        } else {
                            Services.Wallpapers.apply(modelData)
                        }
                    }
                }

                id: cell
            }
        }
    }

    // keep the list fresh when the page opens on a theme whose wallpapers
    // were never scanned this session
    Component.onCompleted: if (!root.themes && Services.Wallpapers.wallpapers.length === 0)
        Services.Wallpapers.scan()
}
