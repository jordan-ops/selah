pragma Singleton
import Quickshell
import QtQuick
import Quickshell.Networking
import Quickshell.Io

Singleton{
    id: root
    readonly property var activeDevice:{
        return Networking.devices.values.find(d => d.connected) || null
    }
    readonly property bool connected: activeDevice !== null

    readonly property bool isWifi: connected && activeDevice.type === DeviceType.Wifi

    readonly property string name:{
        if (!activeDevice) return "Offline"
        const net = activeDevice.networks.values.find(n => n.connected)
        if (net) return net.name
        // wired devices expose no access-point objects — the old
        // "net ? name : Offline" here read a CONNECTED cable as Offline
        return root.isWifi ? "Connected" : "Ethernet"
    }

    // One glyph for every consumer (bar ring, control centre, tiles):
    // three states, not two. Wifi gets the waves; a CONNECTED cable gets
    // md-ethernet (U+F0200, covered by the nerd symbols font) instead of
    // the wifi-OFF glyph it used to show; only a real disconnect gets the
    // crossed waves.
    readonly property string glyph:{
        if (!root.connected) return "󰤭"
        return root.isWifi ? "󰤨" : "󰈀"
    }

    // The wifi radio device itself, regardless of connection state —
    // separate from activeDevice above, which is only set once something
    // is actually connected. Needed to scan for and list nearby networks.
    readonly property var wifiDevice: {
        return Networking.devices.values.find(d => d.type === DeviceType.Wifi) || null
    }

    // Nearby networks. Empty until scan(true) turns scanning on — same
    // idea as a Waybar wifi module only running `nmcli dev wifi list`
    // when you actually open the menu, not on every poll tick.
    readonly property var networks: wifiDevice ? wifiDevice.networks.values : []

    function scan(enabled) {
        if (wifiDevice) wifiDevice.scannerEnabled = enabled
    }

    // Recommended flow per Quickshell's own docs: try connect() first.
    // Already-known/saved networks just work. Ones needing a password
    // Quickshell doesn't have yet fail with connectionFailed(NoSecrets) —
    // listen for that on the network object itself (done in the UI layer)
    // and fall back to connectToNetworkWithPsk().
    function connectToNetwork(network) {
        network.connect()
    }

    function connectToNetworkWithPsk(network, psk) {
        network.connectWithPsk(psk)
    }

    // Waybar analogy: same as a "custom/network" module's on-click running
    // `nmcli radio wifi off`. We don't track "radio enabled" ourselves —
    // `connected` above already updates reactively once NetworkManager
    // actually connects/disconnects, so firing the command is enough.
    // ASSUMPTION: you're on NetworkManager (nmcli). If you're using iwd
    // directly, tell me and I'll swap this to `iwctl station wlan0 ...`.
    function toggleWifi() {
        toggleProc.command = ["nmcli", "radio", "wifi", root.connected ? "off" : "on"]
        toggleProc.running = true
    }

    Process {
        id: toggleProc
    }
}
