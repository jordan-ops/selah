// Ported from Nebula's Widgets/SysForecastWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick
import "shapes/" as MaterialShapes
import "shapes/shape-library.js" as ShapeLibrary

WidgetHost {
    id: root
    configKey: "sysForecast"
    tile: Qt.size(WidgetSizes.span(4), WidgetSizes.span(2.5))
    resizable: true
    minSpan: Qt.size(4, 2.5)
    maxSpan: Qt.size(6, 3.5)
    backdropRadius: (WidgetSizes.radius + 6) * designStage.k
    defaultPos: Qt.point(695, 495)

    readonly property var si: root.preview ? PreviewData : ServiceSystemInfo
    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"

    readonly property real cpu: root.si.cpuUsage
    readonly property real temp: root.si.cpuTemp
    readonly property string mood: root.temp >= 85 ? "hot" : root.cpu >= 0.6 ? "busy" : root.cpu < 0.1 ? "quiet" : "calm"
    readonly property string headline: ({ hot: "Running hot", busy: "Busy spell", quiet: "Clear and quiet", calm: "Mostly calm" })[root.mood]
    readonly property string pressure: root.si.memUsage >= 0.85 ? "heavy" : root.si.memUsage >= 0.6 ? "moderate" : "light"
    readonly property var shape: ShapeLibrary.get(({ hot: "burst", busy: "cookie9", quiet: "circle", calm: "cookie12" })[root.mood])
    readonly property color moodColor: root.mood === "hot" ? Colors.error : root.mood === "busy" ? Colors.tertiary : Colors.primary

    readonly property var columns: {
        if (root.preview) {
            const v = [0.3, 0.22, 0.18, 0.42, 0.58, 0.66, 0.4, 0.34, 0.26, 0.36, 0.44]
            return v.map((x, i) => ({ v: x, label: "13:" + String(30 + i * 5).padStart(2, "0"), now: false }))
                .concat([{ v: 0.38, label: "now", now: true }])
        }
        const b = ServiceSysHistory.buckets.map(e => ({ v: e.v, label: ServiceSysHistory.label(e.at), now: false }))
        const pad = []
        for (let i = b.length; i < ServiceSysHistory.bucketCount - 1; i++)
            pad.push({ v: -1, label: "", now: false })
        return pad.concat(b).concat([{ v: ServiceSysHistory.currentAvg, label: "now", now: true }])
    }
    readonly property real peak: Math.max(0.3, ...root.columns.map(c => c.v))

    Component.onCompleted: {
        root.si.retain()
        if (!root.preview)
            ServiceSysHistory.retain()
    }
    Component.onDestruction: {
        root.si.release()
        if (!root.preview)
            ServiceSysHistory.release()
    }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(420, 270)

        WidgetCard {
            anchors.fill: parent

            Row {
                id: head
                x: parent.pad
                y: parent.pad
                spacing: 16

                Item {
                    width: 92
                    height: 92
                    HiResShape {
                        k: designStage.k
                        anchors.fill: parent
                        polygon: root.shape
                        color: root.moodColor
                    }
                    Rectangle {
                        anchors.centerIn: parent
                        width: 34
                        height: 34
                        radius: 17
                        color: WidgetSizes.cardColor.a > 0.5 ? WidgetSizes.cardColor : Colors.surface
                        Rectangle {
                            anchors.centerIn: parent
                            width: 18
                            height: 18
                            radius: 9
                            color: root.moodColor
                        }
                    }
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2
                    CustomText {
                        content: "NEBULA · RIGHT NOW"
                        size: 12
                        weight: 700
                        font.letterSpacing: 1.4
                        customColor: Colors.outline
                    }
                    CustomText {
                        content: root.headline
                        family: root.display
                        renderType: Text.QtRendering
                        size: 34
                        weight: 400
                    }
                    CustomText {
                        width: 272
                        content: "CPU " + Math.round(root.cpu * 100) + "% · feels like " + Math.round(root.temp) + " °C · " + root.pressure + " memory pressure"
                        size: 13
                        customColor: Colors.surfaceVariantText
                    }
                }
            }

            Row {
                id: cols
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                anchors.margins: parent.pad
                height: parent.height - head.height - parent.pad * 2 - 14
                spacing: 6
                readonly property real cw: (width - spacing * (root.columns.length - 1)) / root.columns.length

                Repeater {
                    model: root.columns
                    delegate: Column {
                        id: col
                        required property var modelData
                        width: cols.cw
                        anchors.bottom: parent.bottom
                        spacing: 5
                        Rectangle {
                            width: parent.width
                            height: col.modelData.v < 0 ? 6 : Math.max(8, (cols.height - 20) * col.modelData.v / root.peak)
                            radius: Math.min(8, width / 2)
                            color: col.modelData.v < 0 ? Colors.surfaceContainerHigh
                                 : col.modelData.now ? root.moodColor
                                 : col.modelData.v / root.peak > 0.8 ? Colors.primary
                                 : col.modelData.v / root.peak > 0.6 ? Colors.primaryContainer
                                 : Colors.secondaryContainer
                            Behavior on height { SpatialAnim {} }
                        }
                        CustomText {
                            anchors.horizontalCenter: parent.horizontalCenter
                            content: col.modelData.label
                            size: 12
                            weight: col.modelData.now ? 700 : 400
                            customColor: col.modelData.now ? Colors.surfaceText : Colors.outline
                        }
                    }
                }
            }
        }
    }
}
