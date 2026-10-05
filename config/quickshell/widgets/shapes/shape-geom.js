.pragma library

// Shape geometry for widgets/shapes/ShapeCanvas.qml — the pure-QML stand-in
// for Nebula's C++ ShapePainter (Nebula shell, GPL-3.0).
//
// Every outline the widget files can ask for (the 37 material-shapes.js
// getters plus the 56 names shape-library.js validates) resolves here to a
// unit outline in -1..1 with y down, inscribed in the box like upstream.
// The families:
//   polar   — cookies/clovers/flowers/scallops are rounded lobes,
//             sunny/burst/boom/stars are pointed rays: r(θ) directly.
//   rounded — polygons (square, gem, shield, bolt, cross…) run through a
//             per-vertex corner-rounding pass, so vertices can opt out
//             with radius 0 (the arch's dome, the semicircle's rim).
//   special — heart (classic parametric curve), leaf (vesica arcs),
//             arch/quarter-fan (arc + straight radii), moon/notch
//             (circle with a gaussian bite), drop (pointed bulb).
// Morphing is an instant swap — upstream interpolated outlines in C++ for
// its 350 ms morph; the widgets only notice a missing animation, never a
// missing shape.

var TAU = Math.PI * 2

var _cache = {}

// ── primitive builders ──────────────────────────────────────────────

function _polar(rFn, n) {
    n = n || 200
    const pts = []
    for (let i = 0; i < n; i++) {
        const t = (i / n) * TAU
        const r = rFn(t)
        pts.push([Math.cos(t) * r, Math.sin(t) * r])
    }
    return pts
}

function _ellipse(a, b) {
    return t => 1 / Math.sqrt(Math.pow(Math.cos(t) / a, 2) + Math.pow(Math.sin(t) / b, 2))
}

function _superellipse(k) {
    return t => Math.pow(
        Math.pow(Math.abs(Math.cos(t)), k) + Math.pow(Math.abs(Math.sin(t)), k),
        -1 / k)
}

// n rounded bumps around the rim — cookies, clovers, flowers, puffy
function _lobed(n, amp, e, phase) {
    return t => 1 - amp * Math.pow(
        0.5 - 0.5 * Math.cos(n * (t + (phase || 0))), e || 0.55)
}

// n pointed rays — sunny, burst, boom, stars. |cos| peaks n times per
// turn, and the exponent sharpens each peak while rounding the valley.
function _spiked(tips, valley, sharp, phase) {
    return t => valley + (1 - valley) * Math.pow(
        Math.abs(Math.cos(tips * (t + (phase || 0)) / 2)), sharp)
}

function _dented(depth, sigma, at) {
    const base = t => {
        let d = (t - (at || 0)) % TAU
        if (d > Math.PI) d -= TAU
        if (d < -Math.PI) d += TAU
        return d
    }
    return t => 1 - depth * Math.exp(-Math.pow(base(t) / sigma, 2))
}

function _arc(cx, cy, r, a0, a1, n) {
    n = n || 40
    const pts = []
    for (let i = 0; i <= n; i++) {
        const a = a0 + (a1 - a0) * (i / n)
        pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r])
    }
    return pts
}

// per-vertex corner rounding: radii is a number or an array, 0 = sharp
function _round(verts, radii, samples) {
    samples = samples || 8
    const out = []
    const N = verts.length
    const rad = i => {
        const r = Array.isArray(radii) ? radii[i % radii.length] : radii
        // only numbers reach the arc maths — a stray non-number (e.g. a
        // caller passing a callback) falls back to a sharp corner rather
        // than poisoning every point with NaN
        return typeof r === "number" ? r : 0
    }
    for (let i = 0; i < N; i++) {
        const cur = verts[i]
        const prev = verts[(i - 1 + N) % N]
        const next = verts[(i + 1) % N]
        const d1x = prev[0] - cur[0], d1y = prev[1] - cur[1]
        const d2x = next[0] - cur[0], d2y = next[1] - cur[1]
        const l1 = Math.hypot(d1x, d1y), l2 = Math.hypot(d2x, d2y)
        if (l1 < 1e-9 || l2 < 1e-9) { out.push(cur); continue }
        const u1x = d1x / l1, u1y = d1y / l1
        const u2x = d2x / l2, u2y = d2y / l2
        const cosA = Math.max(-1, Math.min(1, u1x * u2x + u1y * u2y))
        const A = Math.acos(cosA)
        if (A < 1e-6 || Math.PI - A < 1e-6) { out.push(cur); continue }
        const half = A / 2
        const lim = Math.tan(half) * Math.min(l1, l2) * 0.98
        const r = Math.min(rad(i), lim)
        if (r < 1e-6) { out.push(cur); continue }
        const t = r / Math.tan(half)
        const p1x = cur[0] + u1x * t, p1y = cur[1] + u1y * t
        const p2x = cur[0] + u2x * t, p2y = cur[1] + u2y * t
        let bx = u1x + u2x, by = u1y + u2y
        const bl = Math.hypot(bx, by)
        bx /= bl; by /= bl
        const cd = r / Math.sin(half)
        const cx = cur[0] + bx * cd, cy = cur[1] + by * cd
        const a1 = Math.atan2(p1y - cy, p1x - cx)
        const a2 = Math.atan2(p2y - cy, p2x - cx)
        let d = a2 - a1
        while (d > Math.PI) d -= TAU
        while (d < -Math.PI) d += TAU
        for (let s = 0; s <= samples; s++) {
            const a = a1 + d * (s / samples)
            out.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r])
        }
    }
    return out
}

function _regular(n, phase) {
    const verts = []
    for (let i = 0; i < n; i++) {
        const a = (phase || -Math.PI / 2) + (i / n) * TAU
        verts.push([Math.cos(a), Math.sin(a)])
    }
    return verts
}

// classic parametric heart, scaled to the unit box
function _heart(n) {
    n = n || 220
    const pts = []
    let maxX = 0, minY = 0, maxY = 0
    for (let i = 0; i <= n; i++) {
        const u = (i / n) * TAU
        const x = 16 * Math.pow(Math.sin(u), 3)
        const y = 13 * Math.cos(u) - 5 * Math.cos(2 * u) - 2 * Math.cos(3 * u) - Math.cos(4 * u)
        maxX = Math.max(maxX, Math.abs(x))
        minY = Math.min(minY, y)
        maxY = Math.max(maxY, y)
        pts.push([x, y])
    }
    const sx = 1 / maxX
    const sy = 1 / Math.max(-minY, maxY)
    return pts.map(p => [p[0] * sx, p[1] * sy])
}

// vesica leaf: two arcs meeting in points at (0, ±1)
function _leaf() {
    const c = 0.75, R = Math.hypot(1, c)
    const phi = Math.atan2(1, c)
    const pts = []
    for (let i = 0; i <= 80; i++) {
        const a = -phi + (2 * phi) * (i / 80)
        pts.push([-c + R * Math.cos(a), R * Math.sin(a)])
    }
    for (let i = 80; i >= 0; i--) {
        const a = -phi + (2 * phi) * (i / 80)
        pts.push([c - R * Math.cos(a), R * Math.sin(a)])
    }
    return pts
}

// pointed bulb: circle body, apex pulled to (0, -1)
function _drop() {
    const body = []
    for (let i = 0; i <= 90; i++) {
        const a = -Math.PI / 2 - 1.05 + (2 * 1.05 + Math.PI) * (i / 90)
        body.push([0.82 * Math.cos(a), 0.18 + 0.82 * Math.sin(a)])
    }
    return _round([[0, -1]].concat(body), function () {
        const r = [0.10]
        for (let i = 0; i < 91; i++) r.push(i < 12 || i > 78 ? 0.22 : 0.06)
        return r
    }(), 6)
}

// ── the table ───────────────────────────────────────────────────────

function _build(name) {
    switch (name) {
    case "circle":    return _polar(() => 1, 120)
    case "oval":      return _polar(_ellipse(1, 0.78), 160)
    case "squircle":  return _polar(_superellipse(4), 200)
    case "pill":      return _round([[-1, -0.62], [1, -0.62], [1, 0.62], [-1, 0.62]], 0.62, 14)
    case "square":    return _round([[-1, -1], [1, -1], [1, 1], [-1, 1]], 0.16, 12)
    case "slanted":   return _round([[0.35, -1], [1, -1], [-0.35, 1], [-1, 1]], 0.12, 10)
    case "triangle":  return _round([[0, -1], [1, 0.8], [-1, 0.8]], 0.14, 12)
    case "diamond":   return _round([[0, -1], [1, 0], [0, 1], [-1, 0]], 0.15, 12)
    case "pentagon":  return _round(_regular(5), 0.13, 10)
    case "hexagon":   return _round(_regular(6), 0.12, 10)
    case "octagon":   return _round(_regular(8), 0.10, 8)
    case "clamShell":
    case "semiCircle": {
        const pts = _arc(0, 0, 1, Math.PI, TAU, 60)
        const radii = []
        for (let i = 0; i < pts.length; i++)
            radii.push(i === 0 || i === pts.length - 1 ? 0.10 : 0)
        return _round(pts, radii, 6)
    }
    case "arch": {
        const verts = [[-1, 1], [1, 1], [1, 0]].concat(_arc(0, 0, 1, 0, -Math.PI, 50))
        const radii = [0.14, 0.14, 0]
        for (let i = 3; i < verts.length; i++) radii.push(0)
        return _round(verts, radii, 6)
    }
    case "fan": {
        const verts = [[1, 1], [-1, 1]].concat(_arc(1, 1, 2, Math.PI, 1.5 * Math.PI, 40)).concat([[1, -1]])
        const radii = [0.12, 0]
        for (let i = 2; i < verts.length; i++) radii.push(0)
        return _round(verts, radii, 6)
    }
    case "arrow":
        return _round(
            [[-1, -0.32], [-0.1, -0.32], [-0.1, -1], [1, 0], [-0.1, 1], [-0.1, 0.32], [-1, 0.32]],
            [0.08, 0.07, 0.10, 0.10, 0.10, 0.07, 0.08], 6)
    case "gem":
        return _round([[0, -1], [0.85, -0.35], [0.55, 1], [-0.55, 1], [-0.85, -0.35]], 0.12, 10)
    case "shield":
        return _round([[0, -1], [0.92, -0.55], [0.92, 0.15], [0, 1], [-0.92, 0.15], [-0.92, -0.55]],
            [0.12, 0.10, 0.10, 0.30, 0.10, 0.10], 8)
    case "bolt":
        return _round(
            [[0.25, -1], [-0.5, 0.1], [-0.05, 0.1], [-0.3, 1], [0.55, -0.15], [0.1, -0.15]],
            [0.07, 0.07, 0.06, 0.08, 0.07, 0.06], 6)
    case "chevron":
        return _round(
            [[-0.45, -1], [1, 0], [-0.45, 1], [-1, 1], [0.1, 0], [-1, -1]],
            [0.07, 0.10, 0.07, 0.07, 0.10, 0.07], 6)
    case "cross": {
        const w = 0.32
        return _round([
            [-w, -1], [w, -1], [w, -w], [1, -w], [1, w], [w, w],
            [w, 1], [-w, 1], [-w, w], [-1, w], [-1, -w], [-w, -w]
        ], 0.07, 6)
    }
    case "pixelCircle":
        return _round(
            [[0, -1], [0.62, -1], [1, -0.62], [1, 0.62], [0.62, 1], [0, 1], [-0.62, 1],
             [-1, 0.62], [-1, -0.62], [-0.62, -1]],
            0.04, 4)
    case "pixelTriangle":
        return _round([[0, -1], [1, 1], [-1, 1]], 0.05, 4)
    case "pixelHeart":
        return _heart(180).map(p => [Math.round(p[0] * 7) / 7, Math.round(p[1] * 7) / 7])
    case "heart":      return _heart(220)
    case "leaf":       return _leaf()
    case "drop":       return _drop()
    case "bun":        return _round([[-1, -0.45], [1, -0.45], [1, 0.85], [-1, 0.85]],
                                     [0.55, 0.55, 0.35, 0.35], 14)
    case "ghostish":   return _round([[-0.92, -1], [0.92, -1], [1, 1], [-1, 1]],
                                     [0.55, 0.55, 0.5, 0.5], 14)
    case "sunny":      return _polar(_spiked(8, 0.60, 2.4, -Math.PI / 2))
    case "verySunny":  return _polar(_spiked(12, 0.52, 2.8, -Math.PI / 2))
    case "burst":      return _polar(_spiked(10, 0.70, 1.9, -Math.PI / 2))
    case "softBurst":  return _polar(_spiked(8, 0.74, 1.5, -Math.PI / 2))
    case "boom":       return _polar(_spiked(14, 0.62, 2.2, -Math.PI / 2))
    case "softBoom":   return _polar(_spiked(12, 0.72, 1.6, -Math.PI / 2))
    case "star5":      return _polar(_spiked(5, 0.50, 1.7, -Math.PI / 2))
    case "sparkle":    return _polar(_spiked(4, 0.30, 3.0, -Math.PI / 2))
    case "cookie3":    return _polar(_lobed(3, 0.14, 0.55))
    case "cookie4":    return _polar(_lobed(4, 0.12, 0.55))
    case "cookie5":    return _polar(_lobed(5, 0.11, 0.55))
    case "cookie6":    return _polar(_lobed(6, 0.10, 0.55))
    case "cookie7":    return _polar(_lobed(7, 0.10, 0.55))
    case "cookie8":    return _polar(_lobed(8, 0.09, 0.55))
    case "cookie9":    return _polar(_lobed(9, 0.09, 0.55))
    case "cookie10":   return _polar(_lobed(10, 0.08, 0.55))
    case "cookie12":   return _polar(_lobed(12, 0.08, 0.55))
    case "cookie4ExpandedTL":
        return _polar(t => {
            const boost = 1 + 0.55 * Math.max(0, Math.cos(t + 3 * Math.PI / 4))
            const dip = Math.pow(0.5 - 0.5 * Math.cos(4 * t), 0.55)
            return 1 - 0.12 * boost * dip
        })
    case "clover3":    return _polar(_lobed(3, 0.32, 0.5))
    case "clover4":    return _polar(_lobed(4, 0.30, 0.5))
    case "clover8":    return _polar(_lobed(8, 0.22, 0.5))
    case "scallop":    return _polar(_lobed(12, 0.15, 0.5))
    case "flower":     return _polar(_lobed(6, 0.24, 0.5))
    case "puffy":      return _polar(_lobed(4, 0.19, 0.45))
    case "puffyDiamond": return _polar(_lobed(4, 0.19, 0.45, Math.PI / 4))
    case "blob":       return _polar(t => Math.min(1, 0.88 + 0.09 * Math.cos(3 * t + 1.1)
                                                        + 0.05 * Math.cos(5 * t + 2.3)))
    case "pebble":     return _polar(t => 0.93 + 0.07 * Math.cos(4 * t + 0.8))
    case "moon":       return _polar(_dented(0.58, 0.72, 0))
    case "notch":      return _polar(_dented(0.34, 0.55, -Math.PI / 4))
    default:
        return _polar(() => 1, 120)   // unknown name: circle, like upstream fallbacks
    }
}

// name → unit outline (cached; shapes repeat across widgets)
function points(name) {
    if (!_cache[name]) _cache[name] = _build(name)
    return _cache[name]
}
