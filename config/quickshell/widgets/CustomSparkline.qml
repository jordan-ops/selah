// Ported from Nebula's customComponents/CustomSparkline.qml (GPL-3.0) — qs.modules
// imports dropped (kit now lives beside its users in widgets/).
import QtQuick

Item {
    id: root

    property var values: []
    property int maxPoints: 30
    property color lineColor: Colors.primary
    property color fillColor: Qt.rgba(lineColor.r, lineColor.g, lineColor.b, 0.15)
    property real lineWidth: 1.5
    property bool filled: true
    property real maxOverride: 0
    property real cornerRadius: 6
    property bool gradientFill: true
    property bool logScale: false
    property bool bars: false
    property real barWidth: 2
    property real barGap: 1.5

    function addValue(v) {
        const copy = values.slice()
        copy.push(v)
        if (copy.length > maxPoints) copy.shift()
        values = copy
    }

    Sparkline {
        anchors.fill: parent
        values: root.values
        maxPoints: root.maxPoints
        lineColor: root.lineColor
        areaColor: root.fillColor
        lineWidth: root.lineWidth
        filled: root.filled
        maxOverride: root.maxOverride
        cornerRadius: root.cornerRadius
        gradientFill: root.gradientFill
        logScale: root.logScale
        bars: root.bars
        barWidth: root.barWidth
        barGap: root.barGap
    }
}
