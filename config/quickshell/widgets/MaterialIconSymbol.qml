// Ported from Nebula's customComponents/MaterialIconSymbol.qml (GPL-3.0) — module
// imports dropped (the kit now lives beside its users in widgets/) and
// answers to widgets/Colors + widgets/SettingsConfig, which speak Nebula's
// palette/config names from this shell's theme and store.
import Quickshell
import QtQuick

CustomText{
    id: root
    property real iconSize: 16
    property real fill: 0

    font {
        hintingPreference: Font.PreferFullHinting
        family: "Material Symbols Rounded"
        pixelSize: Math.round(iconSize)
    }
}
