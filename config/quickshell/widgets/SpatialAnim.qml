// Ported from Nebula's customComponents/SpatialAnim.qml (GPL-3.0) — module
// imports dropped (the kit now lives beside its users in widgets/) and
// answers to widgets/Colors + widgets/SettingsConfig, which speak Nebula's
// palette/config names from this shell's theme and store.
import QtQuick

NumberAnimation {
    property string speed: "default"

    duration: M3Motion.spatialDuration(speed)
    easing.type: Easing.BezierSpline
    easing.bezierCurve: M3Motion.spatialCurve(speed)
}
