// Adapter for the ported Nebula widgets (Nebula shell, GPL-3.0): answers
// the member names the widget files bind on, backed by this shell's own
// battery service — no Nebula backend travels with us.
pragma Singleton

import Quickshell
import Quickshell.Io
import QtQuick
import "../services" as Services

Singleton {
    id: root

    readonly property bool hasBattery: Services.Battery.hasBattery
    readonly property bool isCharging: Services.Battery.charging

    // Nebula hands its widgets a 0..1 fraction; our Battery keeps percent
    readonly property real powerLevel: Services.Battery.percent / 100

    // Newest row carrying a real watt reading (sysfs power_now is a
    // magnitude — sign it from the on-AC flag). No reading at all: -1
    // says "unknown", but only while a battery exists — the ring does
    // Math.abs(changeRate ?? 0) and would paint a phantom "1.0 W" on a
    // desktop that has no drain to report.
    readonly property real changeRate: {
        const s = Services.Battery.samples
        for (let i = s.length - 1; i >= 0; i--) {
            const w = s[i][2]
            if (typeof w !== "number")
                continue
            return s[i][3] === 1 ? w : -w
        }
        return root.hasBattery ? -1 : 0
    }

    // Slope the charging streak's charge-% samples and divide what's left
    // by it — no battery-capacity math. A just-plugged-in pack (one row,
    // nothing to slope against) falls through to "—", as does a streak
    // that hasn't gained charge yet.
    readonly property string timeToFull: {
        if (!root.isCharging)
            return ""
        const s = Services.Battery.samples
        if (s.length === 0)
            return "—"
        const newest = s[s.length - 1]
        if (newest[3] !== 1)
            return "—"
        let base = null
        for (let i = s.length - 2; i >= 0; i--) {
            if (s[i][3] !== 1)
                break                      // charging streak ends here
            if (newest[0] - s[i][0] >= 120) {
                base = s[i]                // ≥ 2 min of slope to work with
                break
            }
        }
        const left = 100 - Services.Battery.percent
        if (!base || left <= 0)
            return "—"
        const dt = newest[0] - base[0]
        const dp = newest[1] - base[1]
        const eta = left / (dp / dt)
        if (!(eta > 0) || eta > 172800)    // nonsense or > 48 h
            return "—"
        return Services.Battery.fmtDur(eta)
    }

    // charge_full / charge_full_design, read once at startup. healthRaw
    // keeps the -1 "pack won't say" sentinel for real consumers; the
    // member the ring binds falls back to 1, because that widget prints
    // Math.round(health * 100) + "%" with no guard — a literal -1 would
    // paint "-100%" in the footer. First pack wins if there are several.
    property real healthRaw: -1
    readonly property real health: root.healthRaw >= 0 ? root.healthRaw : 1

    Process {
        id: healthRead
        // sh so the BAT* glob is expanded by the shell, not assumed by us
        command: ["sh", "-c",
                  "cat /sys/class/power_supply/BAT*/charge_full /sys/class/power_supply/BAT*/charge_full_design 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const v = text.trim().split(/\s+/).map(Number)
                root.healthRaw = v.length >= 2 && v[1] > 0 && isFinite(v[0])
                    ? Math.max(0, Math.min(1, v[0] / v[1]))
                    : -1
            }
        }
    }

    Component.onCompleted: healthRead.running = true
}
