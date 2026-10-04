import Quickshell
import Quickshell.Wayland
import QtQuick
import "./services" as Services

// Desktop wallpaper, drawn by quickshell itself — no swww/awww/hyprpaper
// daemon anywhere. Port of omarchy's plugins/background/Background.qml:
// one full-screen window per screen on the compositor's Background layer,
// showing whatever path the Wallpapers service points at.
//
// State lives in ~/.local/state/quickshell/current-wallpaper (one line,
// absolute path) — written by Wallpapers.apply(), by switch-theme.sh on a
// theme switch, or by any script/`qs ipc call wallpaper set`. The
// service's FileView watches the file, so every writer converges here.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: bgWindow
        required property var modelData
        screen: modelData

        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"

        // omarchy's hard-won lesson (their Background.qml): never park the
        // background layer with updates disabled — the surface can lose its
        // committed buffer and leave a black desktop until the shell
        // restarts. The image is static, so correctness beats the small
        // render-loop saving.
        updatesEnabled: true

        WlrLayershell.namespace: "qs-background"
        WlrLayershell.layer: WlrLayer.Background
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        function fileUrl(path) {
            return path !== "" ? "file://" + path : ""
        }

        // base = the wallpaper. `previous` sits on top while the service's
        // crossfade pulls its opacity down to reveal the new base — far
        // fewer moving parts than omarchy's diagonal Shape mask +
        // MultiEffect reveal, same feel; our colors already live-update
        // separately via Colors.qml so there's no theme/background
        // choreography to keep in lockstep here.
        Image {
            id: baseImage
            anchors.fill: parent
            source: bgWindow.fileUrl(Services.Wallpapers.current)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: true
        }

        Image {
            anchors.fill: parent
            source: bgWindow.fileUrl(Services.Wallpapers.previous)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // the previous image was literally on screen a moment ago, so
            // this is a cache hit — no blank flash while base loads
            cache: true
            opacity: Services.Wallpapers.previousOpacity
            visible: source != "" && opacity > 0.001
        }

        // Desktop click ripples — adapted from Nebula (GPL-3.0): the
        // shader refracts the base wallpaper inside each ring and paints
        // an accent-lit crest over it. Hidden entirely while no ripple
        // is alive (services/Ripple.qml owns the slots), so at rest this
        // costs nothing on the GPU. `view` maps the item's UVs onto the
        // PreserveAspectCrop crop of the source texture — same math as
        // Nebula's viewFor(), with img.x always 0 here.
        ShaderEffect {
            id: rippleFx
            anchors.fill: parent
            visible: Services.Ripple.moving

            // only the screen the ripples were spawned on draws them —
            // the pool is global, its coordinates are per-screen
            function rip(i) {
                return Services.Ripple.monitorName === bgWindow.modelData.name
                    ? Services.Ripple.uniformFor(i)
                    : Qt.vector4d(0, 0, -1, 0)
            }

            readonly property vector2d itemSize: Qt.vector2d(width, height)
            readonly property vector4d r0: rip(0)
            readonly property vector4d r1: rip(1)
            readonly property vector4d r2: rip(2)
            readonly property vector4d r3: rip(3)
            readonly property vector4d r4: rip(4)
            readonly property vector4d r5: rip(5)
            readonly property vector4d r6: rip(6)
            readonly property vector4d r7: rip(7)
            readonly property vector4d r8: rip(8)
            readonly property vector4d r9: rip(9)
            readonly property color tint: Services.Colors.accent
            readonly property real strength: Services.Ripple.strength
            readonly property vector4d view: {
                const img = baseImage
                const nw = img.implicitWidth, nh = img.implicitHeight
                if (nw <= 0 || nh <= 0 || img.width <= 0 || img.height <= 0)
                    return Qt.vector4d(0, 0, 1, 1)
                const s = Math.max(img.width / nw, img.height / nh)
                const cx = img.width / (nw * s), cy = img.height / (nh * s)
                return Qt.vector4d((1 - cx) / 2 - img.x / img.width * cx,
                                   (1 - cy) / 2,
                                   width / img.width * cx,
                                   height / img.height * cy)
            }
            readonly property var source: baseImage
            fragmentShader: Qt.resolvedUrl("shaders/ripple.frag.qsb")
        }

        // every left-click (and drag) on the bare desktop becomes a
        // ripple. Declared last = on top of the images; it paints
        // nothing. Windows live on higher layers, so clicks over a
        // window never reach this — ripples only ever appear on the
        // true desktop. Gates (motion off / GameMode) live in spawn().
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            onPressed: mouse =>
                Services.Ripple.spawn(bgWindow.modelData.name, mouse.x, mouse.y, 1)
            onPositionChanged: mouse => {
                if (pressed)
                    Services.Ripple.spawnDrag(bgWindow.modelData.name, mouse.x, mouse.y)
            }
        }
    }
}
