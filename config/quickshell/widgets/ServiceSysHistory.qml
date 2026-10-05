// Adapter for the ported Nebula widgets (Nebula shell, GPL-3.0): answers
// the member names SysForecastWidget binds on (buckets/bucketCount/
// currentAvg/label/retain/release), backed by this shell's own
// ServiceSystemInfo adapter — no Nebula backend travels with us.
//
// Ported from Nebula's services/ServiceSysHistory.qml (GPL-3.0) — qs.modules
// imports dropped (sibling resolution in widgets/).
pragma Singleton

import Quickshell
import QtQuick

Singleton {
    id: root

    readonly property int bucketMs: 300000
    readonly property int bucketCount: 12
    property var buckets: []
    property real peakTemp: 0
    property int _users: 0
    property real _sum: 0
    property int _n: 0
    property real _bucketStart: 0

    function retain() {
        root._users++
        if (root._users === 1) {
            ServiceSystemInfo.retain()
            if (root._bucketStart === 0)
                root._bucketStart = Date.now()
        }
    }

    function release() {
        if (root._users === 0)
            return
        root._users--
        if (root._users === 0)
            ServiceSystemInfo.release()
    }

    function label(ms) {
        return Qt.formatTime(new Date(ms), "hh:mm")
    }

    Timer {
        interval: 10000
        repeat: true
        running: root._users > 0
        triggeredOnStart: true
        onTriggered: {
            root._sum += ServiceSystemInfo.cpuUsage
            root._n++
            root.peakTemp = Math.max(root.peakTemp, ServiceSystemInfo.cpuTemp)
            const now = Date.now()
            if (now - root._bucketStart >= root.bucketMs) {
                const b = root.buckets.concat([{ at: root._bucketStart, v: root._n > 0 ? root._sum / root._n : 0 }])
                root.buckets = b.slice(Math.max(0, b.length - (root.bucketCount - 1)))
                root._sum = 0
                root._n = 0
                root._bucketStart = now
            }
        }
    }

    readonly property real currentAvg: root._n > 0 ? root._sum / root._n : ServiceSystemInfo.cpuUsage
}
