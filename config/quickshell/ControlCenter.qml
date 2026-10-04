pragma Singleton
import Quickshell
import QtQuick
import Quickshell.Io

Singleton {
    id: root
    property bool open: false

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
    }
}
