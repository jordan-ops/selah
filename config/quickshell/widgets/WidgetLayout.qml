pragma Singleton

import Quickshell
import QtQuick

// Ported from Nebula's modules/utils/WidgetLayout.qml (GPL-3.0) — the
// collision manager: every live WidgetHost registers here, drops find the
// nearest overlap-free lattice slot, resizes grow only into free cells and
// "tidy" compacts gaps. Verbatim; the module import is unnecessary now
// (SettingsConfig and WidgetSizes are siblings).
Singleton {
    id: root

    property var hosts: []

    function register(host) {
        if (root.hosts.indexOf(host) < 0) root.hosts = root.hosts.concat([host])
    }

    function unregister(host) {
        root.hosts = root.hosts.filter(h => h !== host)
    }

    function overlaps(ax, ay, aw, ah, bx, by, bw, bh) {
        return ax < bx + bw - 0.5 && bx < ax + aw - 0.5
            && ay < by + bh - 0.5 && by < ay + ah - 0.5
    }

    function isFree(self, x, y, w, h) {
        for (let i = 0; i < root.hosts.length; i++) {
            const o = root.hosts[i]
            if (o === self) continue
            if (root.overlaps(x, y, w, h, o.homeX, o.homeY, o.width, o.height)) return false
        }
        return true
    }

    function nearestFree(self, x, y, w, h) {
        if (root.isFree(self, x, y, w, h)) return Qt.point(x, y)
        const S = WidgetSizes
        const maxC = S.gridCols * 2 - S.halvesCovering(w)
        const maxR = S.gridRows * 2 - S.halvesCovering(h)
        let best = Qt.point(x, y)
        let bestD = Infinity
        for (let c = 0; c <= maxC; c++) {
            for (let r = 0; r <= maxR; r++) {
                const cx = S.originX + c * S.colStep
                const cy = S.originY + r * S.rowStep
                const d = (cx - x) * (cx - x) + (cy - y) * (cy - y)
                if (d < bestD && root.isFree(self, cx, cy, w, h)) {
                    best = Qt.point(cx, cy)
                    bestD = d
                }
            }
        }
        return best
    }

    function firstFree(w, h) {
        const S = WidgetSizes
        const maxC = Math.max(0, S.gridCols - S.cellsCovering(w))
        const maxR = Math.max(0, S.gridRows * 2 - S.halvesCovering(h))
        for (let r = 0; r <= maxR; r++) {
            for (let c = 0; c <= maxC; c++) {
                const x = S.originX + c * S.pitch
                const y = S.originY + r * S.rowStep
                if (root.isFree(null, x, y, w, h))
                    return Qt.point(x, y)
            }
        }
        return Qt.point(S.originX, S.originY)
    }

    function spotAt(col, halfRow, w, h) {
        const S = WidgetSizes
        const c = Math.max(0, Math.min(col, S.gridCols - S.cellsCovering(w)))
        const r = Math.max(0, Math.min(halfRow, S.gridRows * 2 - S.halvesCovering(h)))
        const x = S.originX + c * S.pitch
        const y = S.originY + r * S.rowStep
        if (root.isFree(null, x, y, w, h))
            return Qt.point(x, y)
        return root.nearestFree(null, x, y, w, h)
    }

    function fitSpan(self, x, y, c, r, minC, minR) {
        const S = WidgetSizes
        let best = null
        for (let cc = c; cc >= minC; cc--) {
            for (let rr = r; rr >= minR; rr -= 0.5) {
                if (root.isFree(self, x, y, S.span(cc), S.span(rr))) {
                    if (!best || cc * rr > best.c * best.r) best = { c: cc, r: rr }
                    break
                }
            }
        }
        return best
    }

    function tidyPlan() {
        const S = WidgetSizes
        const g = S.gutter
        const limit = g + S.pitch
        const items = root.hosts.map(h => ({ h: h, x: h.homeX, y: h.homeY, w: h.width, ht: h.height }))

        function clear(it, x, y) {
            return !items.some(o => o !== it && root.overlaps(x, y, it.w, it.ht, o.x, o.y, o.w, o.ht))
        }

        items.slice().sort((a, b) => a.y - b.y).forEach(it => {
            let edge = -1
            items.forEach(o => {
                if (o !== it && o.x < it.x + it.w - 0.5 && it.x < o.x + o.w - 0.5 && o.y + o.ht <= it.y + 0.5)
                    edge = Math.max(edge, o.y + o.ht)
            })
            if (edge < 0) return
            const gap = it.y - edge
            if (gap <= g + 0.5 || gap >= limit) return
            const ny = S.snapY(edge + g, it.ht)
            if (ny < it.y && clear(it, it.x, ny)) it.y = ny
        })

        items.slice().sort((a, b) => a.x - b.x).forEach(it => {
            let edge = -1
            items.forEach(o => {
                if (o !== it && o.y < it.y + it.ht - 0.5 && it.y < o.y + o.ht - 0.5 && o.x + o.w <= it.x + 0.5)
                    edge = Math.max(edge, o.x + o.w)
            })
            if (edge < 0) return
            const gap = it.x - edge
            if (gap <= g + 0.5 || gap >= limit) return
            const nx = S.snapX(edge + g, it.w)
            if (nx < it.x && clear(it, nx, it.y)) it.x = nx
        })

        const patch = {}
        items.forEach(it => {
            if (it.x === it.h.homeX && it.y === it.h.homeY) return
            patch[it.h.configKey + "X"] = it.x
            patch[it.h.configKey + "Y"] = it.y
        })
        return patch
    }

    function tidy() {
        const patch = root.tidyPlan()
        if (Object.keys(patch).length > 0)
            SettingsConfig.widgets = Object.assign({}, SettingsConfig.widgets, patch)
    }
}
