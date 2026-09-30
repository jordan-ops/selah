pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick

// live CPU / RAM / network sampler for the control center's vitals card.
// One /proc read every 2s, deltas computed in QML, rolling 10-minute
// sparkline buffers (300 samples @2s). In-memory only — deliberately not
// persisted: 2s samples would churn the disk for no benefit, and the
// graphs refill within a couple of minutes after a reload.
Singleton {
    id: root

    property real cpu: 0          // %
    property real mem: 0          // %
    property real rx: 0           // B/s down
    property real tx: 0           // B/s up
    property var cpuHist: []
    property var memHist: []

    property var prevCpu: null    // [busy, total] jiffies
    property real prevRx: -1
    property real prevTx: -1
    property real prevT: 0

    readonly property string netUpLabel: fmtRate(tx)
    readonly property string netDownLabel: fmtRate(rx)

    function fmtRate(bps) {
        if (bps < 1024) return Math.round(bps) + " B/s"
        if (bps < 1024 * 1024) return Math.round(bps / 1024) + " KB/s"
        return (bps / (1024 * 1024)).toFixed(1) + " MB/s"
    }

    Process {
        id: probe
        command: ["sh", "-c", "cat /proc/stat /proc/meminfo /proc/net/dev"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text !== "") root.parse(text)
            }
        }
    }

    function parse(raw) {
        const lines = raw.split("\n")
        let i = 0

        // ——— cpu: busy/total deltas from the aggregate "cpu " line ———
        for (i = 0; i < lines.length; i++)
            if (lines[i].startsWith("cpu ")) break
        if (i < lines.length) {
            const f = lines[i].split(/\s+/).slice(1).map(Number)
            const idle = (f[3] || 0) + (f[4] || 0)          // idle + iowait
            const busy = (f[0] || 0) + (f[1] || 0) + (f[2] || 0)
                         + (f[5] || 0) + (f[6] || 0) + (f[7] || 0)
            if (root.prevCpu) {
                const db = busy - root.prevCpu[0]
                const dt = (idle + busy) - root.prevCpu[1]
                if (dt > 0)
                    root.cpu = Math.max(0, Math.min(100, db / dt * 100))
            }
            root.prevCpu = [busy, idle + busy]
        }

        // ——— memory: 1 - MemAvailable/MemTotal ———
        let mt = 0, ma = -1
        for (i = 0; i < lines.length; i++) {
            if (lines[i].startsWith("MemTotal:"))      mt = parseFloat(lines[i].slice(9))
            else if (lines[i].startsWith("MemAvailable:")) ma = parseFloat(lines[i].slice(13))
        }
        if (mt > 0 && ma >= 0)
            root.mem = Math.max(0, Math.min(100, (1 - ma / mt) * 100))

        // ——— network: sum every interface except lo ———
        let rxTot = 0, txTot = 0, inDevs = false
        for (i = 0; i < lines.length; i++) {
            const l = lines[i]
            if (l.includes("Inter-|")) { inDevs = true; continue }
            if (!inDevs || l.includes("face") || l.trim() === "") continue
            const colon = l.indexOf(":")
            if (colon < 0) continue
            if (l.slice(0, colon).trim() === "lo") continue
            const f = l.slice(colon + 1).trim().split(/\s+/)
            rxTot += Number(f[0]) || 0
            txTot += Number(f[8]) || 0
        }
        const now = Date.now() / 1000
        if (root.prevRx >= 0 && now > root.prevT) {
            root.rx = Math.max(0, (rxTot - root.prevRx) / (now - root.prevT))
            root.tx = Math.max(0, (txTot - root.prevTx) / (now - root.prevT))
        }
        root.prevRx = rxTot
        root.prevTx = txTot
        root.prevT = now

        // ——— sparkline buffers (new array each tick → bindings fire) ———
        root.cpuHist = root.cpuHist.concat(root.cpu).slice(-300)
        root.memHist = root.memHist.concat(root.mem).slice(-300)
    }

    function kick() {
        probe.running = false
        probe.running = true
    }

    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: root.kick()
    }

    Component.onCompleted: kick()
}
