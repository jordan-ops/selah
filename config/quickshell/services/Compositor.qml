pragma Singleton
import Quickshell
import Quickshell.Hyprland

// Which compositor owns this session, plus the tiny uniform surface the
// shell's services call so they never have to branch themselves.
//
//   isMango      a mango instance owns the session (its IPC socket is set)
//   isHyprland   Hyprland owns it and mango doesn't
//   monitor      focused monitor — name/x/y/width/height/scale, the subset
//                of Hyprland.focusedMonitor the services actually read
//                (mango's monitor JSON is a superset of that shape)
//   hasFullscreen  the focused window is fullscreen
//   viewTag(n)   switch the view to tag/workspace n
//
// With neither socket present (nested/odd session) it falls back to the
// Hyprland path, which yields null exactly like today — call sites keep
// their `?.` guards.
Singleton {
    id: root

    // NB: Quickshell.env() returns null (not "") for an unset variable,
    // so these must be truthiness tests — `!== ""` would call every
    // Hyprland session "mango" and strand the workspaces strip on the
    // (empty) mango tag list.
    readonly property bool isMango: !!Quickshell.env("MANGO_INSTANCE_SIGNATURE")
    readonly property bool isHyprland: !isMango && !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")

    readonly property var monitor: root.isMango ? Mango.focusedMonitor : Hyprland.focusedMonitor

    readonly property bool hasFullscreen:
        root.isMango
            ? (Mango.focusedClient?.is_fullscreen ?? false)
            : (Hyprland.focusedMonitor?.activeWorkspace?.hasFullscreen ?? false)

    // Focus the given tag (mango) / workspace (Hyprland) on this monitor.
    function viewTag(n) {
        if (root.isMango) Mango.dispatch(`view,${n},0`)
        else Hyprland.dispatch("workspace " + n)
    }
}
