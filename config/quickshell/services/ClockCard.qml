pragma Singleton
import Quickshell
import Quickshell.Hyprland
import QtQuick
import Quickshell.Io

Singleton {
    id: root
    property bool open: false
    // Multi-monitor: overlay state is shared, but every screen has its own
    // bar. The bar that opens this overlay records itself here and only it
    // reacts — without an owner, every bar showed the panel AND armed its
    // own HyprlandFocusGrab; the duplicate grabs fought over keyboard focus
    // and cleared each other the instant they activated, so no panel ever
    // appeared once a second display was connected.
    property string ownerScreen: ""
    onOpenChanged: {
        if (open) {
            const fm = Hyprland.focusedMonitor
            ownerScreen = fm ? fm.name
                : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
        }
    }


    function toggle() { open = !open }
    function close() { open = false }

    // same IPC pattern as ControlCenter/PowerMenu
    IpcHandler {
        target: "clockcard"
        function toggle() { root.toggle() }
    }
}
