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


    // Which advanced device list the side window is showing — "", "network",
    // or "bluetooth". Separate window, separate state, so Bar.qml's second
    // PopupWindow can react without needing a direct binding path across
    // window boundaries — same reasoning as `open` itself being here.
    property string advancedPanel: ""

    function toggle() { open = !open; if (!open) advancedPanel = "" }
    function close() { open = false; advancedPanel = "" }

    function openAdvanced(name) { advancedPanel = (advancedPanel === name) ? "" : name }
    function closeAdvanced() { advancedPanel = "" }

    // same IPC pattern as PowerMenu — lets a Hyprland keybind toggle this too, later
    IpcHandler {
        target: "controlcenter"
        function toggle() { root.toggle() }
        function status(): bool { return root.open }
        // deterministic open for the advanced side panel (toggle-in-toggle
        // safe) — also used by scripts/QA to reach the network/bluetooth
        // panels without synthetic clicks.
        function openPanel(name: string) {
            root.open = true
            root.advancedPanel = name
        }
    }
}
