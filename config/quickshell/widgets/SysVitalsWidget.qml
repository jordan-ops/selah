// Ported from Nebula's Widgets/SysVitalsWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick

WidgetHost {
    id: root
    configKey: "sysVitals"
    tile: Qt.size(WidgetSizes.span(4), WidgetSizes.span(2.5))
    resizable: true
    minSpan: Qt.size(4, 2.5)
    maxSpan: Qt.size(6, 3.5)
    backdropRadius: (WidgetSizes.radius + 6) * designStage.k
    defaultPos: Qt.point(145, 495)

    readonly property var si: root.preview ? PreviewData : ServiceSystemInfo
    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property string mono: SettingsConfig.general.defaultFont
    readonly property var hist: root.preview
        ? [0.3, 0.42, 0.35, 0.5, 0.62, 0.4, 0.36, 0.44, 0.7, 0.52, 0.38, 0.41, 0.33, 0.47]
        : ServiceDashData.cpuHist.slice(-14)

    Component.onCompleted: {
        root.si.retain()
        if (!root.preview)
            ServiceDashData.retainSystem()
    }
    Component.onDestruction: {
        root.si.release()
        if (!root.preview)
            ServiceDashData.releaseSystem()
    }

    component Vital: Column {
        property string label: ""
        property string value: ""
        property color tint: Colors.surfaceText
        spacing: 0
        CustomText { content: parent.label; size: 12; family: "JetBrains Mono"; customColor: parent.tint }
        CustomText {
            content: parent.value
            size: 28
            family: SettingsConfig.general?.displayFont || "Titan One"
            renderType: Text.QtRendering
            weight: 400
            customColor: parent.tint
        }
    }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(420, 270)

        Rectangle {
            anchors.fill: parent
            radius: WidgetSizes.radius + 6
            color: Colors.surfaceContainerLowest
            border.width: 1
            border.color: Colors.surfaceContainer

            Item {
                id: left
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                anchors.margins: 18
                width: parent.width - 36 - 146

                CustomText { content: "LOAD · II"; size: 12; family: root.mono; customColor: Colors.tertiaryContainer }
                CustomText { anchors.right: parent.right; content: "4 s / beat"; size: 12; family: root.mono; customColor: Colors.outlineVariant }

                Canvas {
                    id: trace
                    y: 22
                    readonly property real res: Math.max(1, designStage.k)
                    width: parent.width * res
                    height: 110 * res
                    scale: 1 / res
                    transformOrigin: Item.TopLeft
                    property var samples: root.hist
                    property color ink: Colors.tertiary
                    property color grid: Qt.alpha(Colors.surfaceContainerHigh, 0.7)
                    onSamplesChanged: requestPaint()
                    onInkChanged: requestPaint()
                    onWidthChanged: requestPaint()
                    onPaint: {
                        const ctx = getContext("2d")
                        ctx.reset()
                        ctx.scale(res, res)
                        const lw = width / res
                        const lh = height / res
                        ctx.strokeStyle = grid
                        ctx.lineWidth = 1
                        for (let x = 0.5; x < lw; x += 18) { ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, lh); ctx.stroke() }
                        for (let y = 0.5; y < lh; y += 18) { ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(lw, y); ctx.stroke() }
                        const n = 14
                        const beat = lw / n
                        const base = lh * 0.62
                        ctx.strokeStyle = ink
                        ctx.lineWidth = 2
                        ctx.lineJoin = "round"
                        ctx.beginPath()
                        ctx.moveTo(0, base)
                        const d = samples || []
                        const off = n - d.length
                        let lastX = 0, lastY = base
                        for (let i = 0; i < n; i++) {
                            const x0 = i * beat
                            const v = i >= off ? Math.max(0, Math.min(1, d[i - off])) : -1
                            if (v < 0) {
                                ctx.lineTo(x0 + beat, base)
                                continue
                            }
                            const amp = (0.18 + 0.82 * v) * lh * 0.56
                            ctx.lineTo(x0 + beat * 0.1, base - 4)
                            ctx.lineTo(x0 + beat * 0.18, base)
                            ctx.lineTo(x0 + beat * 0.26, base + 6)
                            ctx.lineTo(x0 + beat * 0.32, base - amp)
                            ctx.lineTo(x0 + beat * 0.39, base + amp * 0.3)
                            ctx.lineTo(x0 + beat * 0.45, base)
                            ctx.lineTo(x0 + beat * 0.62, base)
                            ctx.lineTo(x0 + beat * 0.72, base - 8)
                            ctx.lineTo(x0 + beat * 0.82, base)
                            ctx.lineTo(x0 + beat, base)
                            lastX = x0 + beat
                            lastY = base
                        }
                        ctx.stroke()
                        ctx.fillStyle = Qt.lighter(ink, 1.2)
                        ctx.beginPath()
                        ctx.arc(lastX - 2, lastY, 3.5, 0, Math.PI * 2)
                        ctx.fill()
                    }
                }

                Row {
                    y: 146
                    spacing: 10
                    CustomText {
                        content: Math.round(root.si.cpuUsage * 100)
                        family: root.display
                        renderType: Text.QtRendering
                        size: 60
                        weight: 400
                        customColor: Colors.tertiary
                    }
                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        CustomText { content: "CPU %"; size: 12; family: root.mono; customColor: Colors.tertiaryContainer }
                        CustomText { content: (root.si.cpuName ?? "").replace(/ with .*/, "").replace("AMD ", ""); size: 12; family: root.mono; customColor: Colors.outlineVariant }
                    }
                }

                CustomText {
                    anchors.bottom: parent.bottom
                    content: "nebula · up " + (root.si.uptime ?? "") + " · " + ServiceClock.hour + ":" + ServiceClock.minute
                    size: 12
                    family: root.mono
                    customColor: Colors.outlineVariant
                }
            }

            Column {
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 18
                width: 128
                spacing: 8

                Vital { label: "TEMP °C"; value: Math.round(root.si.cpuTemp); tint: Colors.error }
                Rectangle { width: parent.width; height: 1; color: Colors.surfaceContainer }
                Vital { label: "RAM %"; value: Math.round(root.si.memUsage * 100); tint: Colors.primary }
                Rectangle { width: parent.width; height: 1; color: Colors.surfaceContainer }
                Vital { label: "GPU %"; value: Math.round(root.si.gpuUsage * 100); tint: Colors.secondary }
                Rectangle { width: parent.width; height: 1; color: Colors.surfaceContainer }
                Column {
                    CustomText { content: "NET ↓ / ↑"; size: 12; family: root.mono; customColor: Colors.outline }
                    CustomText {
                        content: root.si.formatNetSpeed(root.si.netDownloadBps).replace(" ", "").replace("/s", "") + " / "
                            + root.si.formatNetSpeed(root.si.netUploadBps).replace(" ", "").replace("/s", "")
                        size: 12
                        family: root.mono
                        customColor: Colors.surfaceVariantText
                    }
                }
            }
        }

        Timer {
            interval: 60000
            running: !root.preview
            repeat: true
            triggeredOnStart: true
            onTriggered: root.si.getUptime()
        }
    }
}
