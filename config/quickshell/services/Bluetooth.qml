pragma Singleton
import Quickshell
import Quickshell.Bluetooth
import QtQuick

// Waybar analogy: this used to be like a "custom/bluetooth" module polling
// `bluetoothctl show` on a timer and parsing text. Turns out Quickshell has
// a native DBus-backed module for this (same idea as Quickshell.Services.Pipewire
// for audio) — adapter.enabled and device.connected update themselves the
// instant bluetoothd's state actually changes. No polling, no Process, no
// busy-guard needed at all.
Singleton {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool powered: adapter?.enabled ?? false

    function toggle() {
        if (adapter) adapter.enabled = !adapter.enabled
    }

    // Devices BlueZ already knows about on the default adapter — paired
    // devices plus anything currently visible. Now backed by real active
    // discovery too: `scan(true)` (below) holds adapter.discovering while
    // a device list is on screen, so brand-new nearby devices show up,
    // not just what BlueZ had already tracked.
    readonly property var devices: adapter ? adapter.devices.values : []

    // Active discovery — BlueZ holds it as a mode, not a one-shot, so
    // the UI that shows a device list must hold `discovering` while its
    // list is on screen and release it when the list goes away (same
    // contract as Services.Network.scan for wifi).
    readonly property bool discovering: adapter?.discovering ?? false

    function scan(enabled) {
        if (adapter && adapter.enabled) adapter.discovering = enabled
    }

    function connectDevice(device) { device.connect() }
    function disconnectDevice(device) { device.disconnect() }
    function pairDevice(device) { device.pair() }
    function forgetDevice(device) { device.forget() }
}
