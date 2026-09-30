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
    // devices plus anything currently visible. ASSUMPTION: there's no
    // confirmed startDiscovery()/scan() function on BluetoothAdapter, so
    // this shows what's already tracked rather than actively hunting for
    // brand-new nearby devices. Fine for a quick-connect picker; revisit
    // if you need "pair a device I've never seen before" from this menu.
    readonly property var devices: adapter ? adapter.devices.values : []

    function connectDevice(device) { device.connect() }
    function disconnectDevice(device) { device.disconnect() }
    function pairDevice(device) { device.pair() }
    function forgetDevice(device) { device.forget() }
}
