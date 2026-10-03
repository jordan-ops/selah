pragma Singleton
import Quickshell
import QtQuick
import Quickshell.Io
import Quickshell.Services.UPower

Singleton{
    id:root
    // A VM or desktop has no laptop battery — UPower still serves a
    // composite displayDevice that reads 0 %, which used to draw a
    // permanent "0%" ring and could trip the low-battery alert. Everything
    // below gates on hasBattery; the bar hides the ring's arc/percentage
    // but keeps the network glyph that lives inside it.
    readonly property bool hasBattery:
        UPower.devices.values.some(d => d.isLaptopBattery)
    readonly property int percent:
        hasBattery && UPower.displayDevice
            ? Math.round(UPower.displayDevice.percentage * 100) : 0
    readonly property bool charging:
        UPower.displayDevice
            ? UPower.displayDevice.state === UPowerDeviceState.Charging : false

    property bool lowBatteryNotified: false   // guards against spamming the same alert repeatedly

    // ——— rolling charge history for the power card ———
    // [[epochSec, pct, watts|null, onAc01], ...] at a 60s cadence,
    // plus an immediate sample whenever the charge state flips (so the
    // curve turns at plug/unplug). 24h retention feeds the stat tiles
    // (on-battery total, longest drain, avg draw); graphSamples is the
    // 2h view the canvas draws. Watts comes from sysfs power_now because
    // upower omits energy-rate while the battery sits idle/full; the
    // charging flag from sysfs status. Legacy 2-element rows [t, pct]
    // still load — watts/flag read as missing downstream. Persisted to
    // disk so everything survives quickshell reloads and reboots.
    readonly property string histPath:
        Quickshell.env("HOME") + "/.local/state/quickshell/battery-history.json"
    property var samples: []
    property int graphMode: 0        // 0 = charge %, 1 = draw watts (card toggle)

    readonly property var graphSamples: {
        const now = Math.floor(Date.now() / 1000)
        return samples.filter(p => p[0] > now - 7200)
    }

    // derived from the flagged rows of the last 24h:
    //   have   — any [t,pct,w,chg] rows exist (else tiles show "—")
    //   onBat  — seconds on battery (flag 0 at both interval ends)
    //   longest— longest continuous drain run, seconds
    //   avgW   — mean draw while on battery, or -1 when never drawn
    readonly property var stats: {
        const now = Math.floor(Date.now() / 1000)
        let onBat = 0, run = 0, longest = 0, wsum = 0, wcnt = 0, flagged = 0
        const s = samples
        for (let i = 0; i < s.length; i++) {
            const p = s[i]
            if (p.length < 4 || p[0] <= now - 86400) continue
            flagged++
            const prevOk = i > 0 && s[i - 1].length >= 4
                           && s[i - 1][3] === 0 && p[3] === 0
            const dt = prevOk ? Math.min(600, p[0] - s[i - 1][0]) : 0
            if (p[3] === 0) {
                onBat += dt
                run += dt
                if (run > longest) longest = run
                if (typeof p[2] === "number" && p[2] > 0) {
                    wsum += p[2]
                    wcnt++
                }
            } else {
                run = 0
            }
        }
        return { have: flagged > 0, onBat: onBat, longest: longest,
                 avgW: wcnt > 0 ? wsum / wcnt : -1 }
    }

    function fmtDur(sec) {
        if (sec < 60) return "0m"
        const h = Math.floor(sec / 3600)
        const m = Math.floor((sec % 3600) / 60)
        return h > 0 ? h + "h " + m + "m" : m + "m"
    }
    readonly property string statsOnBattery: stats.have ? fmtDur(stats.onBat) : "—"
    readonly property string statsLongest:  stats.have ? fmtDur(stats.longest) : "—"
    readonly property string statsAvgW:     stats.avgW >= 0 ? stats.avgW.toFixed(1) + " W" : "—"

    FileView {
        id: histFile
        path: root.histPath
        onLoaded: {
            try {
                const d = JSON.parse(text())
                if (Array.isArray(d.samples)) root.samples = d.samples
            } catch (e) {
                console.log("Battery: history parse —", e)
            }
        }
    }

    Process { id: histWrite }

    function persist() {
        // argv-form (no shell interpolation): printf %s "$1" > "$2"
        histWrite.command = ["sh", "-c", "printf %s \"$1\" > \"$2\"", "histwrite",
                             JSON.stringify({ samples: root.samples }), root.histPath]
        histWrite.running = false
        histWrite.running = true
    }

    // one sysfs read feeds both the watts magnitude and the charge flag
    Process {
        id: sampleRead
        command: ["sh", "-c",
                  "cat /sys/class/power_supply/BAT0/power_now /sys/class/power_supply/BAT0/status"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                const uw = parseFloat(lines[0])
                const status = (lines[1] || "").trim()
                // on-AC whitelist: sysfs prints "Not charging" when the
                // pack is full on AC (and "Full"/"Charging" otherwise) —
                // only a true "Discharging" means on battery
                const onAc = ["Charging", "Not charging", "Full"].includes(status)
                root.commit(root.sampleForce,
                            isNaN(uw) ? null : Math.round(uw / 1e6 * 10) / 10,
                            onAc)
            }
        }
    }
    property bool sampleForce: false

    function grabSample(force) {
        if (!root.hasBattery) return
        sampleForce = force
        sampleRead.running = false
        sampleRead.running = true
    }

    function commit(force, watts, onAc) {
        const now = Math.floor(Date.now() / 1000)
        let s = root.samples.filter(p => p[0] > now - 86400)   // 24h retention
        if (s.length > 1600) s = s.slice(s.length - 1600)
        if (!force && s.length > 0 && now - s[s.length - 1][0] < 20)
            return                                           // coalesce bursts
        s = s.concat([[now, root.percent, watts, onAc ? 1 : 0]])
        root.samples = s
        persist()
    }

    Timer {
        interval: 60000
        running: root.hasBattery
        repeat: true
        onTriggered: root.grabSample(false)
    }

    onPercentChanged: {
        if (!hasBattery) return
        if (percent <= 20 && !charging && !lowBatteryNotified) {
            Quickshell.execDetached(["notify-send", "-u", "critical", "Low Battery", "Battery at " + percent + "%"])
            lowBatteryNotified = true
        }
        // reset the guard once we're back above the threshold or plugged in
        if (percent > 20 || charging) {
            lowBatteryNotified = false
        }
    }

    onChargingChanged: {
        if (!hasBattery) return
        // the "Charging" notification is gone: BatteryRing's chargePulse
        // animation says it quieter (ring waves on plug-in). The
        // low-battery critical above stays — that one you want loud.
        // turn the graph curve immediately at plug/unplug
        grabSample(true)
    }

    Component.onCompleted: grabSample(true)   // seed a flagged sample at startup
}
