pragma Singleton

import Quickshell
import QtQuick

// Ported from Nebula's modules/utils/PreviewData.qml (GPL-3.0) — canned
// readings for widgets rendered in the settings/studio tray. Deliberately
// API-compatible with our ServiceSystemInfo adapter, so a widget swaps the
// whole source with `root.preview ? PreviewData : ServiceSystemInfo` and a
// preview never starts the samplers behind the real service.
Singleton {
    id: root

    readonly property real cpuUsage: 0.42
    readonly property real memUsage: 0.61
    readonly property real memUsedGb: 9.7
    readonly property real memTotalGb: 16.0
    readonly property real cpuTemp: 52
    readonly property string cpuName: "CPU"

    readonly property real diskUsage: 0.73
    readonly property real diskUsedGb: 214
    readonly property real diskTotalGb: 293

    readonly property real gpuUsage: 0.28
    readonly property real gpuTemp: 47
    readonly property real gpuVramUsage: 0.35
    readonly property real gpuVramUsedGb: 2.8
    readonly property real gpuVramTotalGb: 8.0
    readonly property real gpuClockMhz: 1850
    readonly property string gpuName: "GPU"

    readonly property real netDownloadBps: 1.4 * 1024 * 1024
    readonly property real netUploadBps: 320 * 1024
    readonly property real netTotalRxBytes: 4.2 * 1024 * 1024 * 1024
    readonly property real netTotalTxBytes: 0.9 * 1024 * 1024 * 1024

    readonly property string uptime: "3h 12m"
    readonly property real memCacheFrac: 0.19
    readonly property real memBuffersFrac: 0.04
    readonly property var cpuCores: [0.67, 0.86, 0.55, 0.42, 0.25, 0.31, 0.94, 0.08]

    function retain() {}
    function release() {}
    function getUptime() {}

    function formatNetSpeed(bps) {
        if (bps >= 1024 * 1024) return (bps / (1024 * 1024)).toFixed(1) + " MB/s"
        if (bps >= 1024)        return (bps / 1024).toFixed(1) + " KB/s"
        return Math.round(bps) + " B/s"
    }

    function formatBytes(bytes) {
        if (bytes >= 1024 * 1024 * 1024) return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB"
        if (bytes >= 1024 * 1024)        return (bytes / (1024 * 1024)).toFixed(1) + " MB"
        if (bytes >= 1024)               return (bytes / 1024).toFixed(1) + " KB"
        return Math.round(bytes) + " B"
    }
}
