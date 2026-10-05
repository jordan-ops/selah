import QtQuick
import "shape-geom.js" as Geom

// Pure-QML stand-in for Nebula's C++ ShapeCanvas/ShapePainter (Nebula
// shell, GPL-3.0). Widgets set only `roundedPolygon` (a shape NAME from
// material-shapes.js / shape-library.js) and `color`, exactly as before —
// shape-geom.js resolves the name to a unit outline, and this Item fills
// it on a Canvas, inscribed in min(width, height) like upstream.
//
// One fidelity note: the 350 ms outline morph upstream interpolated in
// C++ is an instant swap here. Nothing else about the API moves:
// rotation, anchoring, ShaderEffectSource masking (ShapeWidget renders a
// white copy as its backdrop mask) all behave the same, because it's an
// ordinary Item.
Item {
    id: root

    property var roundedPolygon: null
    property color color: "white"

    implicitWidth: 100
    implicitHeight: 100

    onRoundedPolygonChanged: canvas.requestPaint()
    onColorChanged: canvas.requestPaint()
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
            if (!root.roundedPolygon || width <= 0 || height <= 0) return

            const pts = Geom.points(String(root.roundedPolygon))
            if (!pts || pts.length < 3) return

            // unit outline (-1..1) → box, inscribed AND centered: the
            // origin must move to the middle, otherwise the -x half
            // paints outside the canvas and only its quadrant shows
            const cx = width / 2
            const cy = height / 2
            ctx.beginPath()
            ctx.moveTo(cx + pts[0][0] * cx, cy + pts[0][1] * cy)
            for (let i = 1; i < pts.length; i++)
                ctx.lineTo(cx + pts[i][0] * cx, cy + pts[i][1] * cy)
            ctx.closePath()
            ctx.fillStyle = String(root.color)
            ctx.fill()
        }
    }
}
