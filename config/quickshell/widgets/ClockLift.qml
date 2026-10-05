// Ported from Nebula's Widgets/ClockLift.qml (GPL-3.0) — qs.modules imports
// dropped (everything it used is a sibling in widgets/ now).
import QtQuick
import QtQuick.Effects

Item {
    id: root

    property real strength: 1

    layer.enabled: true
    layer.smooth: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0.03, 0.015, 0.02, 0.62 * root.strength)
        shadowBlur: 0.75
        shadowVerticalOffset: 2
        shadowScale: 1.0
        autoPaddingEnabled: true
    }
}
