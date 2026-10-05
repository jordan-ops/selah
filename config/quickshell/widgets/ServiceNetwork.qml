// Adapter for the ported Nebula widgets (Nebula shell, GPL-3.0): answers
// the member names the widget files bind on, backed by this shell's own
// network service — no Nebula backend travels with us.
pragma Singleton

import Quickshell
import QtQuick
import "../services" as Services

Singleton {
    id: root

    // Material Symbols ligature names — MaterialIconSymbol feeds these
    // straight into the MS font, three states: off / wifi / wired
    readonly property string icon: {
        if (!Services.Network.connected)
            return "signal_wifi_off"
        return Services.Network.isWifi ? "wifi" : "lan"
    }

    // SSID / "Ethernet" / "Offline" already reads as a label to the veil
    readonly property string connectionLabel: Services.Network.name

    // passthroughs for anything else that binds Nebula's names directly
    readonly property bool connected: Services.Network.connected
    readonly property bool isWifi: Services.Network.isWifi
    readonly property string name: Services.Network.name
    readonly property string glyph: Services.Network.glyph
    readonly property var activeDevice: Services.Network.activeDevice
    readonly property var wifiDevice: Services.Network.wifiDevice
}
