import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot{
    id: root

    // Bar visibility — SUPER+H via `qs ipc call bar toggle`.
    // Lives up here (not in Bar.qml) so there is exactly ONE handler and
    // ONE flag: a handler inside the Variants would be cloned per screen
    // and toggle would fire once per bar. Session-only: a quickshell
    // restart shows the bar again. Hiding the PanelWindow unmaps its
    // layer surface, so Hyprland drops the exclusive zone with it and
    // windows reflow into the freed strip. Hiding ALSO closes any open
    // pill panel + the tray chevron (nothing on an unmapped surface can
    // receive its click-away or Escape), while asking for a panel while
    // hidden unhides the bar again — see the Connections and
    // onPanelOpenChanged in Bar.qml.
    property bool barVisible: true

    IpcHandler {
        target: "bar"
        // "unhide", not "show": the qs CLI reserves `show` for its own
        // listing subcommand — `qs ipc call bar show` never reaches us.
        function unhide(): void { root.barVisible = true }
        function hide(): void { root.barVisible = false }
        function toggle(): void { root.barVisible = !root.barVisible }
    }

    Background{}
    Bar{ barVisible: root.barVisible; onUnhideRequested: root.barVisible = true }
    LockScreen{}
    AetherPicker{}   // aether wallpaper/palette overlay — qs ipc call aether toggle
    RepoUpdatePopup{}   // "a new deploy is ready" dialog — qs ipc call updates status
    // Polkit prompt merged into the bar (pill "polkit" mode in Bar.qml,
    // like the launcher) — PolkitDialog.qml deprecated, kept as reference.
    // MediaBar{}
    // NotificationBar {}
    // Motion tokens (Material 3 Expressive durations/beziers/springs): services/Motion.qml
}
