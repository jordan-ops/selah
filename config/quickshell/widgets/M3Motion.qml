pragma Singleton
pragma ComponentBehavior: Bound
import Quickshell
import QtQuick

// Ported from Nebula's modules/settings/M3Motion.qml (GPL-3.0) — Material-3
// motion tokens, verbatim: durations, bezier curves and the reveal sweep the
// arrange mode is built on. Only its one settings read (motionScheme) is
// redirected — SettingsConfig.general.motionScheme answers "expressive" here,
// which is upstream's default too.
Singleton {
    id: root

    property string scheme: SettingsConfig.general.motionScheme ?? "expressive"
    readonly property bool expressive: root.scheme !== "standard"

    property QtObject spatial
    property QtObject effects
    property QtObject container
    property QtObject reveal
    property QtObject panel

    container: QtObject {
        readonly property int duration: 360
        readonly property int radiusDuration: 200
        readonly property int crossFadeDuration: 210
        readonly property var curve: [0.53, 0.47, 0.53, 1.06, 1, 1]
        readonly property var alphaOut: [0.0, 0.0, 0.8, 1.0, 1, 1]
        readonly property var alphaIn: [0.4, 0.0, 1.0, 1.0, 1, 1]
    }

    // A mode reveal that travels across the screen: one pass of light, no overshoot
    // (a sweep that bounces reads as a mistake), and leaving is about half as long.
    panel: QtObject {
        readonly property int openDuration: root.expressive ? 600 : 450
        readonly property int closeDuration: 380
        readonly property var openCurve: root.expressive ? [0.38, 1.21, 0.22, 1.00, 1, 1]
                                                         : [0.2, 0.0, 0.0, 1.0, 1, 1]
        readonly property var closeCurve: [0.3, 0.0, 0.8, 0.15, 1, 1]
    }

    readonly property var emphasizedCurve: [0.05, 0, 0.133333, 0.06, 0.166666, 0.4,
                                            0.208333, 0.82, 0.25, 1, 1, 1]

    reveal: QtObject {
        readonly property int duration: 760
        readonly property int outDuration: 340
        readonly property real band: 0.45
        readonly property var curve: [0.2, 0.0, 0.0, 1.0, 1, 1]
    }

    spatial: QtObject {
        readonly property int fastDuration:    root.expressive ? 350 : 220
        readonly property int defaultDuration: root.expressive ? 500 : 315
        readonly property int slowDuration:    root.expressive ? 650 : 480

        readonly property var fastCurve:    root.expressive ? [0.42, 1.67, 0.21, 0.90, 1, 1]
                                                            : [0.25, 0.35, 0.11, 1.14, 1, 1]
        readonly property var defaultCurve: root.expressive ? [0.38, 1.21, 0.22, 1.00, 1, 1]
                                                            : [0.25, 0.35, 0.11, 1.14, 1, 1]
        readonly property var slowCurve:    root.expressive ? [0.39, 1.29, 0.35, 0.98, 1, 1]
                                                            : [0.25, 0.35, 0.11, 1.14, 1, 1]
    }

    effects: QtObject {
        readonly property int fastDuration:    150
        readonly property int defaultDuration: 230
        readonly property int slowDuration:    325
        readonly property var curve: [0.24, 0.36, 0.10, 1.10, 1, 1]
    }

    function spatialDuration(speed) {
        if (speed === "fast") return root.spatial.fastDuration
        if (speed === "slow") return root.spatial.slowDuration
        return root.spatial.defaultDuration
    }

    function spatialCurve(speed) {
        if (speed === "fast") return root.spatial.fastCurve
        if (speed === "slow") return root.spatial.slowCurve
        return root.spatial.defaultCurve
    }

    function effectsDuration(speed) {
        if (speed === "fast") return root.effects.fastDuration
        if (speed === "slow") return root.effects.slowDuration
        return root.effects.defaultDuration
    }
}
