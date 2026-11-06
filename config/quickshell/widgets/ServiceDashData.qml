// Adapter for the ported Nebula widgets (Nebula shell, GPL-3.0): answers
// the member names the widget files bind on, backed by this shell's own
// vitals service — no upstream backend travels with us.
pragma Singleton

import Quickshell
import QtQuick
import "../services" as Services

Singleton {
    id: root

    // Upstream plots 0..1 fractions (SysVitals clamps its trace to 0..1 and
    // DashLayout scales tempHist by /100); our sampler keeps percent, so
    // convert here or the trace pins flat at full height at any load.
    readonly property var cpuHist: Services.Vitals.cpuHist.map(v => v / 100)
    readonly property var memHist: Services.Vitals.memHist.map(v => v / 100)

    // Retain/release forwards to Vitals — the shared 2 s /proc probe is
    // demand-gated, so a widget mount is what keeps it (and the history
    // buffers behind cpuHist/memHist) alive.
    function retainSystem() {
        Services.Vitals.retain()
    }

    function releaseSystem() {
        Services.Vitals.release()
    }

    // Histories we don't collect: empty keeps every consumer well-formed
    // (the dash spreads them into Math.max(1024, ...hists))
    readonly property var gpuHist: []
    readonly property var tempHist: []
    readonly property var netDownHist: []
    readonly property var netUpHist: []
    readonly property var processes: []

    // matches our 300-sample (10 min @ 2 s) buffers
    readonly property int historyPoints: 300
}
