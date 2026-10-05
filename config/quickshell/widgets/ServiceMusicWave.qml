// Adapter for the ported Nebula widgets (Nebula shell, GPL-3.0): answers
// the member names MusicWaveformWidget binds on (captured/seed/cell/retain/
// release).
//
// Ported from Nebula's services/ServiceMusicWave.qml (GPL-3.0) — qs.modules
// imports dropped (sibling resolution in widgets/).
//
// Nebula filled `captured` from ServiceCava, a live audio spectrum we don't
// ship (nothing in this shell exposes one). With no spectrum the adapter
// serves Nebula's own no-data path unchanged: `captured` stays at -1 so
// cell() falls back to the deterministic per-track `seed`, giving a
// track-shaped wave rather than an empty row — the widget's own progress
// highlight then does the rest. retain()/release() keep the refcount the
// widget expects but start no sampler.
pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    readonly property int count: 120
    property var captured: []
    property int _users: 0

    readonly property real total: ServiceMusic.trackLength
    readonly property string key: (ServiceMusic.activeTrack?.title ?? "") + "|" + (ServiceMusic.activeTrack?.artist ?? "")

    onKeyChanged: root.reset()
    Component.onCompleted: root.reset()

    function retain() {
        root._users++
    }

    function release() {
        if (root._users === 0)
            return
        root._users--
    }

    function reset() {
        const a = []
        for (let i = 0; i < root.count; i++)
            a.push(-1)
        root.captured = a
    }

    readonly property var seed: {
        let h = 2166136261
        for (let i = 0; i < root.key.length; i++) {
            h ^= root.key.charCodeAt(i)
            h = Math.imul(h, 16777619) >>> 0
        }
        const a = (h % 97) / 9, b = (h % 31) / 5, c = (h % 13) / 3
        const out = []
        for (let i = 0; i < root.count; i++) {
            const v = 0.5 + 0.28 * Math.sin(i * 0.23 + a) + 0.16 * Math.sin(i * 0.071 + b) + 0.1 * Math.sin(i * 0.61 + c)
            out.push(Math.max(0.14, Math.min(1, v)))
        }
        return out
    }

    function cell(i, bars) {
        const lo = Math.floor(i * root.count / bars)
        const hi = Math.max(lo + 1, Math.floor((i + 1) * root.count / bars))
        let best = -1, seedMax = 0
        for (let k = lo; k < hi && k < root.count; k++) {
            best = Math.max(best, root.captured[k] ?? -1)
            seedMax = Math.max(seedMax, root.seed[k] ?? 0)
        }
        return best >= 0 ? { v: best, real: true } : { v: seedMax * 0.55, real: false }
    }
}
