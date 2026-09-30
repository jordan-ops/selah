pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

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


    // the power menu's data now lives here, not inline in Bar.qml —
    // same reasoning as Themes.qml holding the theme list instead of
    // Bar.qml hardcoding it
    readonly property var actions: [
        // Hyprland's lua config provider parses hyprctl dispatch args as Lua
        // expressions since 0.56 — the legacy "dispatch exit" string errors
        // ("syntax might need to be updated") and silently logs out nothing.
        { icon: "󰍃", command: ["hyprctl", "dispatch", "hl.dsp.exit()"] },
        { icon: "󰜉", command: ["systemctl", "reboot"] },
        { icon: "󰐥", command: ["systemctl", "poweroff"] }
    ]

    IpcHandler {
        target: "powermenu"
        function toggle(): void {
            root.open = !root.open
        }
        function status(): bool {
            return root.open
        }
    }
}
