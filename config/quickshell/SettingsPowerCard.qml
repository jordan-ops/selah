import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Material battery card — the `powercard` row type. One elevated card
// instead of four info rows: big charge %, state chip, a rolling charge
// HISTORY GRAPH (Services.Battery samples every 60 s over a 2h window —
// climbs while charging, sags while draining; the segmented %/W toggle
// swaps the series to draw-over-time), then six tonal tiles — the three
// readings plus on-battery/longest-drain/avg-draw usage stats, and
// estimate (UNTIL FULL / REMAINING), DRAWING (energy rate) and HEALTH
// (upower capacity). Tile values come from one `upower -i battery_BAT0`
// read, re-polled every 10 s while the row is on screen (the ListView
// destroys offscreen delegates, so the timer pauses itself for free).
// upower omits time while the battery is full; the estimate tile then
// derives hours from energy/rate when a load is present, else "—".
Item {
    id: root

    property var e: null

    property real pct: -1
    property string stateRaw: ""
    property string timeVal: ""
    property string wattVal: ""
    property real health: -1
    property real rate: -1      // energy-rate in W (upower prints "energy-rate:")
    property real energy: -1    // current Wh
    property real energyFull: -1

    readonly property bool charging: stateRaw === "charging"
    readonly property bool discharging: stateRaw === "discharging"
    readonly property bool full: stateRaw === "fully-charged"

    readonly property string stateText: {
        if (charging) return "Charging"
        if (discharging) return "Discharging"
        if (full) return "Full"
        if (stateRaw.startsWith("pending")) return "Plugged in"
        return "—"
    }
    readonly property string timeCap:
        charging ? "UNTIL FULL" : (discharging ? "REMAINING" : "ESTIMATE")
    readonly property string healthVal: health >= 0 ? Math.round(health) + "%" : "—"
    readonly property bool healthWarn: health >= 0 && health < 70
    // upower only reports time while actually charging/discharging; when
    // it's silent but a load/charge current is flowing, derive it from
    // energy ÷ rate so the tile is never blank for no reason.
    readonly property string timeShown: {
        if (timeVal !== "") return timeVal
        if (rate > 0 && energy >= 0) {
            const raw = charging ? Math.max(0, energyFull - energy) : energy
            const hrs = raw / rate
            if (isFinite(hrs) && hrs > 0 && hrs < 1000)
                return hrs.toFixed(1) + " hours"
        }
        return "—"
    }

    readonly property bool hasBat: Services.Battery.hasBattery
    readonly property real extraHeight: hasBat ? Math.max(0, col.implicitHeight - 64) : 12
    height: hasBat ? col.implicitHeight : 76

    function read() { if (!root.hasBat) return; rd.running = true }

    Component.onCompleted: read()

    Process {
        id: rd
        command: ["upower", "-i", "/org/freedesktop/UPower/devices/battery_BAT0"]
        stdout: StdioCollector {
            onStreamFinished: {
                let st = "", pct = -1, tt = "", wr = "", hp = -1, en = -1, ef = -1, rt = -1
                const lines = text.split("\n")
                for (let i = 0; i < lines.length; i++) {
                    const t = lines[i].trim()
                    if (t.startsWith("state:"))              st = t.slice(6).trim()
                    else if (t.startsWith("percentage:"))     pct = parseFloat(t.slice(11))
                    else if (t.startsWith("time to empty:"))  tt = t.slice(14).trim()
                    else if (t.startsWith("time to full:"))   tt = t.slice(13).trim()
                    // upower prints "energy-rate:" (hyphen) — the old space
                    // variant never matched, which is why DRAWING was always "—"
                    else if (t.startsWith("energy-rate:") || t.startsWith("energy rate:")) {
                        wr = t.slice(t.indexOf(":") + 1).trim()
                        rt = parseFloat(wr)
                    }
                    else if (t.startsWith("energy-full:"))    ef = parseFloat(t.slice(12))
                    else if (t.startsWith("energy:"))         en = parseFloat(t.slice(7))
                    else if (t.startsWith("capacity:"))       hp = parseFloat(t.slice(9))
                }
                root.stateRaw = st
                root.pct = isNaN(pct) ? -1 : pct
                root.timeVal = tt
                root.wattVal = wr
                root.health = isNaN(hp) ? -1 : hp
                root.rate = isNaN(rt) ? -1 : rt
                root.energy = isNaN(en) ? -1 : en
                root.energyFull = isNaN(ef) ? -1 : ef
            }
        }
    }

    Timer { interval: 10000; running: root.hasBat; repeat: true; onTriggered: root.read() }

    Column {
        id: col
        visible: root.hasBat
        width: parent.width
        spacing: 10

        Item { width: 1; height: 50 }   // clears the row's label block

        Rectangle {
            id: card
            width: col.width
            height: cardCol.implicitHeight + 28
            radius: 16
            color: Services.Colors.surface
            border.color: Services.Colors.low
            border.width: 1

            Column {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 14
                spacing: 12

                // headline — big % + state chip
                Row {
                    width: cardCol.width
                    height: 32
                    spacing: 10

                    Text {
                        font.family: Services.Fonts.family
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pct >= 0 ? Math.round(root.pct) + "%" : "—"
                        font.pixelSize: 24
                        font.bold: true
                        color: root.charging ? Services.Colors.accent
                             : (root.discharging && root.pct >= 0 && root.pct <= 10
                                ? Services.Colors.critical : Services.Colors.text)
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: stateRow.implicitWidth + 20
                        height: 22
                        radius: 11
                        color: Services.Colors.surfaceAlt

                        Row {
                            id: stateRow
                            anchors.centerIn: parent
                            spacing: 6

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 6
                                height: 6
                                radius: 3
                                color: root.charging || root.full ? Services.Colors.accent
                                     : (root.pct >= 0 && root.pct <= 10 && root.discharging
                                        ? Services.Colors.critical : Services.Colors.textMuted)
                            }
                            Text {
                                font.family: Services.Fonts.family
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.stateText
                                font.pixelSize: 11
                                font.bold: true
                                color: Services.Colors.text
                            }
                        }
                    }

                    Item { width: parent.width
                           height: 1 }   // spacer
                }

                // charge history graph — climbs while charging, sags while
                // draining. Data = Services.Battery's 60s/2h sampler; the
                // flat-line fallback keeps it meaningful before the first
                // samples land.
                Item {
                    width: cardCol.width
                    height: 72

                    Canvas {
                        id: graph
                        anchors.fill: parent
                        antialiasing: true
                        opacity: 0

                        property var hist: Services.Battery.graphSamples
                        property bool chg: Services.Battery.charging
                        property int cur: root.pct
                        property int mode: Services.Battery.graphMode
                        onHistChanged: requestPaint()
                        onChgChanged: requestPaint()
                        onCurChanged: requestPaint()
                        onModeChanged: requestPaint()
                        onWidthChanged: requestPaint()
                        Component.onCompleted: fadeIn.start()

                        NumberAnimation {
                            id: fadeIn
                            target: graph
                            property: "opacity"
                            to: 1
                            duration: Services.Motion.effects
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Services.Motion.emphasizedDecelerate
                        }

                        function rgba(c, a) {
                            return "rgba(" + Math.round(c.r * 255) + ","
                                 + Math.round(c.g * 255) + "," + Math.round(c.b * 255)
                                 + "," + a + ")"
                        }

                        onPaint: {
                            const ctx = getContext("2d")
                            const w = width, h = height
                            ctx.clearRect(0, 0, w, h)

                            const pad = 6
                            const ih = h - 2 * pad
                            const acc = Services.Colors.accent
                            const lowc = Services.Colors.low
                            const pctMode = graph.mode === 0
                            const s0 = graph.hist || []

                            // y-scale: fixed 0-100 for %; dynamic 0-maxW
                            // for watts (rounded up to a 5W step)
                            let maxV = 100
                            if (!pctMode) {
                                let mx = 0
                                for (let i = 0; i < s0.length; i++) {
                                    const wv = s0[i][2]
                                    if (typeof wv === "number" && wv > mx) mx = wv
                                }
                                if (root.rate > mx) mx = root.rate
                                maxV = Math.max(5, Math.ceil(mx / 5) * 5)
                            }
                            const val = q => {
                                if (pctMode) return q[1]
                                return typeof q[2] === "number" ? q[2] : null
                            }
                            const toY = v => pad + (1 - Math.max(0, Math.min(maxV, v)) / maxV) * ih

                            const critical = pctMode && root.discharging && root.pct >= 0 && root.pct <= 10
                            const stroke = critical ? Services.Colors.critical
                                         : (pctMode || Services.Battery.charging ? acc
                                            : Services.Colors.textMuted)

                            // tonal guides at 25 / 50 / 75 % of the scale
                            ctx.lineWidth = 1
                            ctx.strokeStyle = graph.rgba(lowc, 0.45)
                            ctx.setLineDash([2, 5])
                            const guides = [0.25, 0.5, 0.75]
                            for (let gi = 0; gi < guides.length; gi++) {
                                const gy = Math.round(pad + (1 - guides[gi]) * ih) + 0.5
                                ctx.beginPath()
                                ctx.moveTo(0, gy)
                                ctx.lineTo(w, gy)
                                ctx.stroke()
                            }
                            ctx.setLineDash([])

                            // sample history → pixel points (W mode skips
                            // rows without a watts value; flat fallback at
                            // the live reading until data exists)
                            const s = s0
                            let pts = []
                            if (s.length >= 2) {
                                const t0 = s[0][0], t1 = s[s.length - 1][0]
                                const span = Math.max(1, t1 - t0)
                                for (let i = 0; i < s.length; i++) {
                                    const v = val(s[i])
                                    if (v === null) continue
                                    pts.push([(s[i][0] - t0) / span * w, toY(v)])
                                }
                            }
                            if (pts.length < 2) {
                                const fb = pctMode
                                    ? (s.length === 1 ? s[0][1] : root.pct)
                                    : Math.max(0, root.rate)
                                const y = toY(fb)
                                pts = [[0, y], [w, y]]
                            }

                            // area fill
                            const grd = ctx.createLinearGradient(0, 0, 0, h)
                            grd.addColorStop(0, graph.rgba(stroke, 0.28))
                            grd.addColorStop(1, graph.rgba(stroke, 0.02))
                            ctx.beginPath()
                            ctx.moveTo(pts[0][0], h)
                            for (let i = 0; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1])
                            ctx.lineTo(pts[pts.length - 1][0], h)
                            ctx.closePath()
                            ctx.fillStyle = grd
                            ctx.fill()

                            // line
                            ctx.beginPath()
                            ctx.moveTo(pts[0][0], pts[0][1])
                            for (let i = 1; i < pts.length; i++) ctx.lineTo(pts[i][0], pts[i][1])
                            ctx.lineWidth = 2
                            ctx.lineJoin = "round"
                            ctx.lineCap = "round"
                            ctx.strokeStyle = stroke
                            ctx.stroke()

                            // live head dot, ringed in card color
                            const last = pts[pts.length - 1]
                            ctx.beginPath()
                            ctx.arc(Math.max(3, last[0] - 3), last[1], 4.5, 0, Math.PI * 2)
                            ctx.fillStyle = Services.Colors.surface
                            ctx.fill()
                            ctx.beginPath()
                            ctx.arc(Math.max(3, last[0] - 3), last[1], 3, 0, Math.PI * 2)
                            ctx.fillStyle = stroke
                            ctx.fill()
                        }
                    }
                }

                // six tonal tiles — live readings + usage stats derived
                // from Battery's 24h sampler (on-battery, longest drain,
                // average draw)
                Row {
                    width: cardCol.width
                    spacing: 8

                    Repeater {
                        model: [
                            { cap: root.timeCap, val: root.timeShown },
                            { cap: "DRAWING",     val: root.wattVal !== "" ? root.wattVal : "—" },
                            { cap: "HEALTH",      val: root.healthVal, warn: root.healthWarn },
                            { cap: "ON BATTERY",  val: Services.Battery.statsOnBattery },
                            { cap: "LONGEST",     val: Services.Battery.statsLongest },
                            { cap: "AVG DRAW",    val: Services.Battery.statsAvgW }
                        ]

                        delegate: Item {
                            width: (cardCol.width - 40) / 6
                            height: 46

                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: Services.Colors.surfaceAlt
                            }
                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.top: parent.top
                                anchors.topMargin: 7
                                spacing: 3

                                Text {
                                    font.family: Services.Fonts.family
                                    text: modelData.cap
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 1.2
                                    color: Services.Colors.textMuted
                                }
                                Text {
                                    font.family: Services.Fonts.family
                                    text: modelData.val
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: modelData.warn ? Services.Colors.critical
                                                         : Services.Colors.text
                                    elide: Text.ElideRight
                                    width: parent.width - 4
                                }
                            }
                        }
                    }
                }
            }
            // segmented % / W toggle over the graph — swaps Battery.graphMode
            // (tonal track, raised active chip, ColorAnimation glides)
            Rectangle {
                id: segCtl
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: 14
                anchors.topMargin: 14
                width: 74
                height: 24
                radius: 12
                color: Services.Colors.surfaceAlt

                Rectangle {
                    id: segP
                    anchors.left: parent.left
                    anchors.leftMargin: 3
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    height: 18
                    radius: 9
                    color: Services.Battery.graphMode === 0 ? Services.Colors.surface : "transparent"
                    Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                    Text {
                        font.family: Services.Fonts.family
                        anchors.centerIn: parent
                        text: "%"
                        font.pixelSize: 11
                        font.bold: true
                        color: Services.Battery.graphMode === 0 ? Services.Colors.accent : Services.Colors.textMuted
                        Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Battery.graphMode = 0
                    }
                }

                Rectangle {
                    id: segW
                    anchors.left: segP.right
                    anchors.verticalCenter: parent.verticalCenter
                    width: 34
                    height: 18
                    radius: 9
                    color: Services.Battery.graphMode === 1 ? Services.Colors.surface : "transparent"
                    Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }

                    Text {
                        font.family: Services.Fonts.family
                        anchors.centerIn: parent
                        text: "W"
                        font.pixelSize: 11
                        font.bold: true
                        color: Services.Battery.graphMode === 1 ? Services.Colors.accent : Services.Colors.textMuted
                        Behavior on color { ColorAnimation { duration: Services.Motion.effectsFast; easing.type: Easing.BezierSpline; easing.bezierCurve: Services.Motion.emphasizedDecelerate } }
                    }

                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Battery.graphMode = 1
                    }
                }
            }
        }
    }

    // no battery on this machine (VM / desktop box): the card collapses to
    // one honest line instead of a grid of "0%" tiles
    Text {
        visible: !root.hasBat
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.topMargin: 50
        font.family: Services.Fonts.family
        font.pixelSize: 12
        color: Services.Colors.textMuted
        text: "No battery on this machine — it runs on AC."
    }
}