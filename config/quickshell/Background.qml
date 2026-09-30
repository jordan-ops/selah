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
    }
}
