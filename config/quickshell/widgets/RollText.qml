// Ported from Nebula's Widgets/RollText.qml (GPL-3.0) — qs.modules imports
// dropped (everything it used is a sibling in widgets/ now).
import QtQuick

Item {
    id: root

    property string text: ""
    property string family: "Rubik"
    property int pixelSize: 40
    property int weight: 600
    property color color: Colors.surfaceText
    property real letterSpacing: 0
    property real lineHeight: 1
    property real travel: root.pixelSize * 0.32
    property bool animated: true
    property int horizontalAlignment: Text.AlignLeft

    property bool _ready: false
    property string _first: ""
    readonly property var _segments: root._split(root.text)

    function _split(s) {
        const out = []
        let run = ""
        for (const ch of s) {
            if (ch >= "0" && ch <= "9") {
                if (run !== "")
                    out.push(run)
                run = ""
                out.push(ch)
            } else {
                run += ch
            }
        }
        if (run !== "")
            out.push(run)
        return out
    }

    implicitWidth: row.implicitWidth
    implicitHeight: row.implicitHeight
    clip: false

    component Face: Text {
        color: root.color
        font.family: root.family
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        font.letterSpacing: root.letterSpacing
        font.features: { "tnum": 1 }
        lineHeight: root.lineHeight
        renderType: Text.QtRendering
    }

    Row {
        id: row
        x: root.horizontalAlignment === Text.AlignRight ? root.width - row.implicitWidth
            : root.horizontalAlignment === Text.AlignHCenter ? (root.width - row.implicitWidth) / 2
            : 0

        Repeater {
            model: root._segments.length

            delegate: Item {
                id: slot

                required property int index
                property string value: root._segments[slot.index] ?? ""
                property bool _b: false
                property bool _live: false
                readonly property Text _cur: slot._b ? fb : fa

                implicitWidth: slot._cur.implicitWidth
                implicitHeight: slot._cur.implicitHeight

                Face { id: fa }
                Face { id: fb; opacity: 0 }

                Component.onCompleted: {
                    fa.text = slot.value
                    slot._live = true
                    if (root._ready && root.animated && root.text !== root._first) {
                        inY.target = fa; inO.target = fa
                        outY.target = fb; outO.target = fb
                        swap.restart()
                    }
                }

                onValueChanged: {
                    if (!slot._live)
                        return
                    const out = slot._cur
                    const inn = slot._b ? fa : fb
                    inn.text = slot.value
                    slot._b = !slot._b
                    if (!root.animated) {
                        swap.stop()
                        out.opacity = 0
                        out.y = 0
                        inn.opacity = 1
                        inn.y = 0
                        return
                    }
                    outY.target = out; outO.target = out
                    inY.target = inn; inO.target = inn
                    swap.restart()
                }

                ParallelAnimation {
                    id: swap
                    NumberAnimation { id: outY; property: "y"; from: 0; to: -root.travel; duration: 260; easing.type: Easing.InCubic }
                    NumberAnimation { id: outO; property: "opacity"; from: 1; to: 0; duration: 200; easing.type: Easing.InCubic }
                    NumberAnimation { id: inY; property: "y"; from: root.travel; to: 0; duration: 520; easing.type: Easing.BezierSpline; easing.bezierCurve: [0.05, 0.7, 0.1, 1.0, 1, 1] }
                    NumberAnimation { id: inO; property: "opacity"; from: 0; to: 1; duration: 360; easing.type: Easing.OutCubic }
                }
            }
        }
    }

    Component.onCompleted: {
        root._first = root.text
        root._ready = true
    }
}
