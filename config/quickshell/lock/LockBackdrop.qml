import QtQuick
import QtQuick.Effects
import "../services" as Services

// The shared lock backdrop every style draws first: the live desktop
// wallpaper, blurred, a themed scrim over it, and the click-anywhere
// layer that (re)focuses the password field.
//
// Two knobs the lock itself doesn't use:
//   softBlur    false in the settings preview — a full-resolution blur
//               samples every frame the settings window is open, and
//               the sharp copy reads fine at thumbnail size.
//   interactive false in the preview: there is no password to focus
//               there, and the click layer must not steal clicks from
//               the settings window.
Item {
    id: backdrop
    anchors.fill: parent

    // LockScreen root in the real lock (carries focusPassword()); the
    // preview passes a plain object with the same shape.
    property var lock: null
    property bool interactive: true
    property bool softBlur: true

    // theme dirs are user-chosen — encode each segment so a space in a
    // directory name doesn't truncate the source at that byte
    function fileUrl(path) {
        if (path === "") return ""
        return "file://" + String(path).split("/").map(encodeURIComponent).join("/")
    }

    Image {
        id: wall
        anchors.fill: parent
        source: backdrop.fileUrl(Services.Wallpapers.current)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        // cap the decode at surface size — MultiEffect samples this every
        // frame the lock is up, so anything larger is waste
        sourceSize.width: width
        sourceSize.height: height
        // REQUIRED by QtQuick.Effects: MultiEffect draws a second,
        // separate item *alongside* its source rather than replacing it.
        // With both visible the sharp image sits under the blur and shows
        // through wherever the blur samples past the edge of the surface.
        // Preview (no blur) shows this copy instead — that's the flip.
        visible: !backdrop.softBlur
    }

    // Blur parameters mirror omarchy's plugins/lock/LockView.qml — the
    // source this lock was adapted from. autoPaddingEnabled MUST be false
    // here: Qt's own guidance is that with it on, a full-screen blur
    // "grows outside the window / screen". blurMultiplier rather than a
    // bigger blurMax, per the same performance note (bigger blurMax costs
    // texture lookups).
    MultiEffect {
        anchors.fill: parent
        visible: backdrop.softBlur
        source: wall
        autoPaddingEnabled: false
        // gate on Ready so the shader isn't sized against an image that
        // hasn't decoded yet
        blurEnabled: backdrop.softBlur && wall.status === Image.Ready
        blur: 1.0
        blurMax: 128
        blurMultiplier: 1.25
        contrast: -0.08
    }

    // Scrim: the clock is 150px in Colors.text and the field label is
    // 13px, both straight over the wallpaper. A blurred bright image
    // would otherwise put light-on-light behind them. Themed background
    // rather than plain black so it tints to the palette instead of
    // greying the wallpaper out.
    Rectangle {
        anchors.fill: parent
        color: Services.Colors.background
        opacity: 0.4
    }

    MouseArea {
        anchors.fill: parent
        enabled: backdrop.interactive
        onClicked: if (backdrop.lock) backdrop.lock.focusPassword()
    }
}
