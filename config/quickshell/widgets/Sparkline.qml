// Pure-QML port of Nebula's C++ Sparkline (plugins/Nebula/sparkline.cpp,
// GPL-3.0) — CustomSparkline.qml binds this type verbatim, so the API and
// every drawing rule below follow the original line for line: right-aligned
// line/area chart with rounded joins (canvas arcTo ≡ the C++ canvasArcTo
// helper), 0.9 height headroom, gradient-or-flat fill, log1p normalisation,
// and the pill-capped bar mode with its 55 %-alpha history.
import QtQuick

Item {
    id: root

    property var values: []
    property int maxPoints: 30
    property color lineColor: "white"
    property color areaColor: "transparent"
    property real lineWidth: 1.5
    property bool filled: true
    property real maxOverride: 0
    property real cornerRadius: 6
    property bool gradientFill: true
    property bool logScale: false
    property bool bars: false
    property real barWidth: 2
    property real barGap: 1.5

    onValuesChanged: canvas.requestPaint()
    onMaxPointsChanged: canvas.requestPaint()
    onLineColorChanged: canvas.requestPaint()
    onAreaColorChanged: canvas.requestPaint()
    onLineWidthChanged: canvas.requestPaint()
    onFilledChanged: canvas.requestPaint()
    onMaxOverrideChanged: canvas.requestPaint()
    onCornerRadiusChanged: canvas.requestPaint()
    onGradientFillChanged: canvas.requestPaint()
    onLogScaleChanged: canvas.requestPaint()
    onBarsChanged: canvas.requestPaint()
    onBarWidthChanged: canvas.requestPaint()
    onBarGapChanged: canvas.requestPaint()
    onWidthChanged: canvas.requestPaint()
    onHeightChanged: canvas.requestPaint()

    Canvas {
        id: canvas
        anchors.fill: parent
        antialiasing: true

        onPaint: {
            const ctx = getContext("2d")
            ctx.reset()
            ctx.clearRect(0, 0, width, height)

            const vals = root.values
            if (!vals || vals.length < 2 || width <= 0 || height <= 0) return

            const w = width, h = height
            let peak = vals[0]
            for (let i = 1; i < vals.length; i++)
                if (vals[i] > peak) peak = vals[i]
            const maxVal = root.maxOverride > 0 ? root.maxOverride : Math.max(peak, 1.0)

            const norm = v => root.logScale
                ? Math.log1p(Math.max(0, v)) / Math.log1p(maxVal)
                : v / maxVal

            const rgba = (c, a) => Qt.rgba(c.r, c.g, c.b, a)

            if (root.bars) {
                const slot = root.barWidth + root.barGap
                const count = Math.max(1, Math.floor((w + root.barGap) / slot))
                const first = Math.max(0, vals.length - count)
                const shown = vals.length - first

                for (let i = 0; i < shown; i++) {
                    const bh = Math.max(2, norm(vals[first + i]) * h * 0.95)
                    const x = w - (shown - i) * slot + root.barGap
                    ctx.fillStyle = i === shown - 1
                        ? String(root.lineColor) : String(rgba(root.lineColor, 0.55))
                    ctx.beginPath()
                    ctx.roundRect(x, h - bh, root.barWidth, bh, root.barWidth / 2)
                    ctx.fill()
                }
                return
            }

            const n = vals.length
            const stepX = w / Math.max(1, root.maxPoints - 1)
            const offsetX = (root.maxPoints - n) * stepX
            const r = Math.min(root.cornerRadius, stepX / 2)
            const pt = i => [offsetX + i * stepX, h - norm(vals[i]) * h * 0.9]

            // traced from `start` (0 for the line, 1 to begin with lineTo
            // for the area) — mirrors the C++ trace lambda
            const trace = move => {
                const p0 = pt(0)
                if (move) ctx.moveTo(p0[0], p0[1])
                else ctx.lineTo(p0[0], p0[1])
                for (let i = 1; i < n - 1; i++) {
                    const p = pt(i), pn = pt(i + 1)
                    if (r > 0.01) ctx.arcTo(p[0], p[1], pn[0], pn[1], r)
                    else ctx.lineTo(p[0], p[1])
                }
                const pl = pt(n - 1)
                ctx.lineTo(pl[0], pl[1])
            }

            if (root.filled) {
                ctx.beginPath()
                const p0 = pt(0)
                ctx.moveTo(p0[0], h)
                trace(false)
                const pl = pt(n - 1)
                ctx.lineTo(pl[0], h)
                ctx.closePath()
                ctx.fillStyle = root.gradientFill
                    ? (function () {
                          const g = ctx.createLinearGradient(0, 0, 0, h)
                          g.addColorStop(0, rgba(root.lineColor, 0.2))
                          g.addColorStop(1, rgba(root.lineColor, 0))
                          return g
                      })()
                    : String(root.areaColor)
                ctx.fill()
            }

            ctx.beginPath()
            trace(true)
            ctx.strokeStyle = String(root.lineColor)
            ctx.lineWidth = root.lineWidth
            ctx.lineCap = "round"
            ctx.lineJoin = "round"
            ctx.stroke()
        }
    }
}
