pragma Singleton
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick

// "Keep screen awake" — the Control Center tile (qs ipc call keepawake
// toggle) for long videos, renders or downloads you're watching. Two
// belts: Screensaver.qml refuses to launch while this is active, and a
// 0x0 surface advertises the Wayland idle-inhibit protocol so Hyprland
// and any other idle consumer backs off too.
//
// Runtime-only on purpose — a shell restart always comes back with idle
// protection armed; a forgotten keep-awake must never outlive the
// session.
Singleton {
    id: root

    property bool active: false
    function toggle() { root.active = !root.active }

    IdleInhibitor {
        enabled: root.active
        window: PanelWindow {
            implicitWidth: 0
            implicitHeight: 0
            color: "transparent"
            mask: Region {}
        }
    }

    IpcHandler {
        target: "keepawake"
        function toggle(): void { root.toggle() }
        function status(): bool { return root.active }
    }
}
