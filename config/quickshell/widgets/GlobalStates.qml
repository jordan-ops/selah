pragma Singleton
pragma ComponentBehavior: Bound
import QtQuick
import Quickshell

// Ported from Nebula's modules/settings/GlobalStates.qml (GPL-3.0) — the
// widget-arrange state machine, kept almost verbatim so WidgetScreen /
// WidgetStudio / WidgetHost talk to the names they expect. Trimmed to what
// the widget system uses (arrange mode, stage, backdrop, desktop cursor,
// the desktopClicked/Dragged signals) plus the two flags widgets peek at
// (fileDialogOpen, settingsOpen); the dock/launcher machinery upstream
// carried never travelled with us.
Singleton {
    id: root

    property bool settingsOpen: false
    property int  settingsPage: 9
    property bool fileDialogOpen: false
    property bool fileDropOpen: false

    property bool widgetEditMode: false
    // Blueprint sweep for widget arrange mode: 0 = off, 1 = fully revealed. Every
    // consumer (grid canvas, scrim, hint bar, each widget's chrome) derives its own
    // local progress from this one number and its own x, so they cannot drift apart.
    property real widgetEditReveal: root.widgetEditMode ? 1 : 0
    Behavior on widgetEditReveal {
        NumberAnimation {
            duration: root.widgetEditMode ? M3Motion.reveal.duration : M3Motion.reveal.outDuration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: M3Motion.reveal.curve
        }
    }

    function revealAt(centreX, screenW) {
        const r = root.widgetEditReveal
        if (screenW <= 0)
            return r
        const band = M3Motion.reveal.band
        const nx = centreX / screenW
        return Math.max(0, Math.min(1, (r * (1 + band) - nx) / band))
    }

    property string widgetSettingsKey: ""
    property int widgetSection: 0
    property string widgetStudioTab: "layout"
    property real widgetStageScale: 1
    property point widgetStageOrigin: Qt.point(0, 0)
    property point widgetQuickAdd: Qt.point(-1, -1)
    property bool widgetOpenAdd: false

    onWidgetEditModeChanged: {
        if (root.widgetEditMode)
            return
        root.widgetQuickAdd = Qt.point(-1, -1)
        root.widgetOpenAdd = false
        root.widgetSettingsKey = ""
        root.widgetStudioTab = "layout"
    }

    // True only while a desktop widget's text field holds focus. Drives the
    // widget layer's keyboard mode so it never holds the keyboard at rest.
    property bool widgetTextFocus: false

    // Wallpaper crop each widget paints as its frosted backdrop —
    // WidgetScreen fills these from our current wallpaper.
    property var widgetBackdrop: null
    property var widgetBackdropSharp: null
    property vector2d widgetScreenSize: Qt.vector2d(1920, 1080)

    property real desktopCursorX: 0
    property real desktopCursorY: 0
    property bool desktopCursorActive: false

    signal desktopClicked(string screenName, real x, real y)
    signal desktopDragged(string screenName, real x, real y)
}
