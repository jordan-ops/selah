pragma Singleton
import Quickshell
import Quickshell.Io
import QtQuick
import "../services" as Services

// Adapter for the ported Nebula widgets (Nebula shell, GPL-3.0): answers
// the member names the widget files bind on, backed by this shell's own
// services — no Nebula C++ SystemStats plugin travels with us.
//
// Aggregates (cpu/mem %, rx/tx) come from services/Vitals so the control
// center and the widgets can never disagree. The extras Nebula's C++ plugin
// carried — per-core jiffies, meminfo totals, CPU temp, disk, GPU — are
// sampled here by one bash loop that only runs while a widget retains the
// service (widgets call retain()/release() on mount/unmount, exactly like
// upstream's refcount). Usage values are 0..1 fractions, matching
// Nebula's stats surface; temps are °C; bytes are raw.
Singleton {
    id: root

    // ── shared with services/Vitals (always live, fraction units) ────
    readonly property real cpuUsage: Services.Vitals.cpu / 100
    readonly property real memUsage: Services.Vitals.mem / 100
    readonly property real netDownloadBps: Services.Vitals.rx
    readonly property real netUploadBps: Services.Vitals.tx
    // string surface for display: our Network service's `name` (SSID or
    // device name, "Offline" when disconnected) — Nebula's raw interface
    // name has no consumer in the ported set
    readonly property string netInterface: Services.Network.name

    // ── sampled extras (populated while retained) ────────────────────
    property real memUsedGb: 0
    property real memTotalGb: 0
    property real memCacheFrac: 0
    property real memBuffersFrac: 0
    property var cpuCores: []
    property real cpuTemp: 0
    property real diskUsage: 0
    property real diskUsedGb: 0
    property real diskTotalGb: 0
    property real gpuUsage: 0
    property real gpuTemp: 0
    property real gpuVramUsage: 0
    property real gpuVramUsedGb: 0
    property real gpuVramTotalGb: 0
    property real gpuClockMhz: 0
    property string gpuName: ""
    property string cpuName: ""
    property real netTotalRxBytes: 0
    property real netTotalTxBytes: 0
    property string uptime: ""

    property var _prevCores: []
    property int _refCount: 0

    function retain() { _refCount++ }
    function release() {
        if (_refCount > 0) _refCount--
    }

    // upstream copies — the graph window maths must agree with what the
    // widget buckets, so these formulas stay verbatim
    readonly property int netWindowMinutes: {
        const n = parseInt(SettingsConfig.widgets?.networkGraphWindow ?? "3")
        return (isNaN(n) || n <= 0) ? 3 : n
    }

    readonly property int netSampleIntervalMs: {
        const n = parseInt(SettingsConfig.widgets?.networkGraphInterval ?? "2")
        return Math.max(1000, Math.min(60000, (isNaN(n) || n <= 0 ? 2 : n) * 1000))
    }

    readonly property int _netRawPoints:
        Math.max(1, Math.round(root.netWindowMinutes * 60000 / root.netSampleIntervalMs))

    readonly property int netSamplesPerPoint: Math.max(1, Math.ceil(root._netRawPoints / 240))

    readonly property int netHistoryPoints:
        Math.max(2, Math.round(root._netRawPoints / root.netSamplesPerPoint))

    signal netSampled()

    function formatNetSpeed(bps) {
        if (bps >= 1024 * 1024) return (bps / (1024 * 1024)).toFixed(1) + " MB/s"
        if (bps >= 1024)        return (bps / 1024).toFixed(1) + " KB/s"
        return bps.toFixed(1) + " B/s"
    }

    function formatBytes(bytes) {
        if (bytes >= 1024 * 1024 * 1024) return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB"
        if (bytes >= 1024 * 1024)        return (bytes / (1024 * 1024)).toFixed(1) + " MB"
        if (bytes >= 1024)               return (bytes / 1024).toFixed(1) + " KB"
        return bytes.toFixed(0) + " B"
    }

    // graph ticks at the user's chosen interval (Vitals' 2s samples feed it)
    Timer {
        running: root._refCount > 0
        interval: root.netSampleIntervalMs
        repeat: true
        onTriggered: root.netSampled()
    }

    function getUptime() {
        uptimeProc.running = true
        return uptime
    }

    Process {
        id: uptimeProc
        command: ["bash", "-c", "uptime -p | sed 's/up //' | sed 's/ hours*/h/' | sed 's/ minutes*/m/' | sed 's/,//g'"]

        property string buffer: ""

        stdout: SplitParser {
            onRead: data => uptimeProc.buffer = data
        }

        onExited: {
            root.uptime = uptimeProc.buffer
            uptimeProc.buffer = ""
        }
    }

    // one-shot identity reads — cheap enough to always run, and widgets
    // like SystemMonitorCompact show the name without retaining
    Process {
        running: true
        command: ["bash", "-c", "grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //'"]
        stdout: SplitParser { onRead: data => root.cpuName = data }
    }

    Process {
        running: true
        command: ["bash", "-c", "lspci | grep -i vga | sed 's/.*: //' | tail -1"]
        stdout: SplitParser { onRead: data => root.gpuName = data }
    }

    // ── the sampler ───────────────────────────────────────────────────
    // One bash loop, 4s cadence. Every 8th tick refreshes disk, every
    // 16th the dGPU (nvidia-smi is slow on this Optimus laptop, so it
    // never runs per-tick, and its N/A fields on the old GK208M fall
    // back to 0 in _num()). Killed the moment nothing retains us.
    Process {
        id: sampler
        running: root._refCount > 0
        command: ["bash", "-c", `T=0
while :; do
  cores=$(awk '/^cpu[0-9]+ /{tot=0; for(i=2;i<=9;i++) tot+=$i; printf "%s:%d:%d ", $1, tot-$5-$6, tot}' /proc/stat)
  mem=$(awk '/^MemTotal:/{t=$2}/^MemAvailable:/{a=$2}/^Cached:/{c=$2}/^Buffers:/{b=$2}END{printf "%d:%d:%d:%d",t,a,c,b}' /proc/meminfo)
  net=$(awk -F: 'NR>2{gsub(/^[ \\t]+/,"",$2); if($1!="lo"){split($2,f," "); rx+=f[1]; tx+=f[9]}}END{printf "%d:%d",rx,tx}' /proc/net/dev)
  temp=""
  for z in /sys/class/thermal/thermal_zone*; do
    ty=$(cat "$z/type" 2>/dev/null)
    v=$(cat "$z/temp" 2>/dev/null)
    case "$ty" in *pkg*|*x86*|*cpu*) temp=$v;; esac
    [ -z "$temp" ] && [ -n "$v" ] && temp=$v
  done
  printf 'S|%s|%s|%s|%s\\n' "$cores" "$mem" "$net" "$temp"
  if [ $((T % 8)) -eq 0 ]; then
    df -P / | awk 'NR==2{printf "D|%.3f:%.3f:%.3f\\n", $3/1048576, ($3+$4)/1048576, $3/($3+$4)}'
  fi
  if [ $((T % 16)) -eq 0 ]; then
    g=$(nvidia-smi --query-gpu=utilization.gpu,temperature.gpu,memory.used,memory.total,clocks.sm --format=csv,noheader,nounits 2>/dev/null | head -1)
    [ -n "$g" ] && printf 'G|%s\\n' "$g"
  fi
  T=$((T+1))
  sleep 4
done`]

        stdout: SplitParser { onRead: line => root._onLine(line) }
    }

    function _num(s) {
        const v = parseFloat(String(s).replace(/[^0-9.\-]/g, ""))
        return isNaN(v) ? 0 : v
    }

    function _onLine(line) {
        if (line.length === 0) return

        if (line[0] === "S") {
            const p = line.split("|")          // S|cores|mem|net|temp
            if (p.length < 5) return

            // per-core busy/total deltas → 0..1 fractions
            const prev = root._prevCores
            const cur = []
            p[1].trim().split(/\s+/).forEach((tok, i) => {
                const c = tok.split(":")
                const b = Number(c[1]), t = Number(c[2])
                let f = 0
                const pv = prev[i]
                if (pv && t > pv[1]) f = Math.max(0, Math.min(1, (b - pv[0]) / (t - pv[1])))
                else if (pv) f = pv[2]         // counter wrap: hold last value
                cur.push([b, t, f])
            })
            root._prevCores = cur
            root.cpuCores = cur.map(c => c[2])

            const m = p[2].split(":")           // kB: total avail cached buffers
            const total = Number(m[0])
            if (total > 0) {
                root.memTotalGb = total / 1048576
                root.memUsedGb = (total - Number(m[1])) / 1048576
                root.memCacheFrac = Number(m[2]) / total
                root.memBuffersFrac = Number(m[3]) / total
            }

            const n = p[3].split(":")           // cumulative rx:tx bytes
            if (n.length >= 2) {
                root.netTotalRxBytes = Number(n[0])
                root.netTotalTxBytes = Number(n[1])
            }

            root.cpuTemp = root._num(p[4]) / 1000
            return
        }

        if (line[0] === "D") {
            const d = line.slice(2).split(":")  // usedGB:totalGB:usage
            if (d.length >= 3) {
                root.diskUsedGb = Number(d[0])
                root.diskTotalGb = Number(d[1])
                root.diskUsage = Number(d[2])
            }
            return
        }

        if (line[0] === "G") {
            const g = line.slice(2).split(",")  // util,temp,mused,mtotal,clock
            if (g.length >= 5) {
                root.gpuUsage = Math.max(0, Math.min(1, root._num(g[0]) / 100))
                root.gpuTemp = root._num(g[1])
                root.gpuVramUsedGb = root._num(g[2]) / 1024
                root.gpuVramTotalGb = root._num(g[3]) / 1024
                root.gpuVramUsage = root.gpuVramTotalGb > 0
                    ? root.gpuVramUsedGb / root.gpuVramTotalGb : 0
                root.gpuClockMhz = root._num(g[4])
            }
            return
        }
    }
}
