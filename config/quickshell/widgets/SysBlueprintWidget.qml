// Ported from Nebula's Widgets/SysBlueprintWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import QtQuick
import QtQuick.Shapes

WidgetHost {
    id: root
    configKey: "sysBlueprint"
    tile: Qt.size(WidgetSizes.span(4), WidgetSizes.span(2.5))
    resizable: true
    minSpan: Qt.size(4, 2.5)
    maxSpan: Qt.size(6, 3.5)
    backdropRadius: (WidgetSizes.radius + 6) * designStage.k
    defaultPos: Qt.point(695, 165)

    readonly property var si: root.preview ? PreviewData : ServiceSystemInfo
    readonly property string display: SettingsConfig.general?.displayFont || "Titan One"
    readonly property var cores: root.si.cpuCores.length > 0 ? root.si.cpuCores : [root.si.cpuUsage]
    readonly property string cpuModel: {
        const m = String(root.si.cpuName ?? "").match(/\b(\d{4}[A-Z]{0,2})\b/)
        return m ? m[1] : "CPU"
    }
    readonly property color line: Colors.outline

    Component.onCompleted: root.si.retain()
    Component.onDestruction: root.si.release()

    component Label: CustomText {
        size: 12
        weight: 700
        font.letterSpacing: 1.4
    }

    WidgetDesignStage {
        id: designStage
        anchors.fill: parent
        design: Qt.size(420, 270)

        Rectangle {
            id: board
            anchors.fill: parent
            radius: WidgetSizes.radius + 6
            color: Colors.surfaceContainerLow
            border.width: 1
            border.color: Colors.surfaceContainerHighest
            clip: true

            Canvas {
                readonly property real res: Math.max(1, designStage.k)
                width: parent.width * res
                height: parent.height * res
                scale: 1 / res
                transformOrigin: Item.TopLeft
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    const ctx = getContext("2d")
                    ctx.reset()
                    ctx.scale(res, res)
                    ctx.strokeStyle = Qt.alpha(Colors.outlineVariant, 0.45)
                    ctx.lineWidth = 1
                    for (let x = 20.5; x < width; x += 20) {
                        ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
                    }
                    for (let y = 20.5; y < height; y += 20) {
                        ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
                    }
                }
            }

            Shape {
                anchors.fill: parent
                preferredRendererType: Shape.CurveRenderer
                ShapePath {
                    strokeColor: root.line
                    strokeWidth: 1.5
                    fillColor: "transparent"
                    startX: 169.6; startY: 83.6
                    PathLine { x: 207.6; y: 83.6 }
                    PathLine { x: 207.6; y: 50.5 }
                    PathLine { x: 237.7; y: 50.5 }
                }
                ShapePath {
                    strokeColor: root.line
                    strokeWidth: 1.5
                    fillColor: "transparent"
                    startX: 169.6; startY: 130.6
                    PathLine { x: 207.6; y: 130.6 }
                    PathLine { x: 207.6; y: 165.5 }
                    PathLine { x: 237.7; y: 165.5 }
                }
                ShapePath {
                    strokeColor: root.line
                    strokeWidth: 1.5
                    fillColor: "transparent"
                    startX: 169.6; startY: 235.2
                    PathLine { x: 317; y: 235.2 }
                    PathLine { x: 317; y: 202.1 }
                }
            }

            Repeater {
                model: [Qt.point(207.6, 83.6), Qt.point(207.6, 165.5), Qt.point(317, 235.2)]
                delegate: Rectangle {
                    required property point modelData
                    x: modelData.x - 3
                    y: modelData.y - 3
                    width: 4.8
                    height: 5.2
                    radius: 3
                    color: root.line
                }
            }

            Rectangle {
                x: 19
                y: 20.9
                width: 150.6
                height: 174.2
                radius: 14
                color: "transparent"
                border.width: 2
                border.color: Colors.primary

                Label {
                    x: 9.5; y: 10.5
                    content: "CPU · " + root.cpuModel
                    customColor: Colors.primary
                }
                CustomText {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    y: 7
                    content: Math.round(root.si.cpuUsage * 100) + "%"
                    family: root.display
                    renderType: Text.QtRendering
                    size: 16
                    weight: 400
                    customColor: Colors.primary
                }

                Grid {
                    id: coreGrid
                    x: 9.5
                    y: 29.6
                    width: parent.width - 24
                    height: parent.height - 64
                    columns: Math.max(1, Math.ceil(root.cores.length / 2))
                    spacing: 6
                    readonly property real cw: (width - (columns - 1) * spacing) / columns
                    readonly property real ch: (height - spacing) / 2

                    Repeater {
                        model: root.cores
                        delegate: Rectangle {
                            id: core
                            required property real modelData
                            readonly property bool hot: modelData >= 0.9
                            width: coreGrid.cw
                            height: coreGrid.ch
                            radius: 5
                            color: "transparent"
                            border.width: 1.5
                            border.color: core.hot ? Colors.error : Colors.outline
                            clip: true
                            Rectangle {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                anchors.margins: 2
                                height: Math.max(0, (parent.height - 4) * core.modelData)
                                radius: 3
                                color: Qt.alpha(core.hot ? Colors.error : Colors.primary, 0.55)
                                Behavior on height { SpatialAnim {} }
                            }
                        }
                    }
                }

                Label {
                    x: 9.5
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 10
                    content: root.cores.length + " THREADS · " + Math.round(root.si.cpuTemp) + " °C"
                    customColor: Colors.outline
                }
            }

            Item {
                x: 237.7
                y: 26.1
                width: 163.2
                height: 61

                Label { content: "MEMORY"; customColor: Colors.tertiary }
                Label {
                    anchors.right: parent.right
                    content: root.si.memUsedGb.toFixed(1) + " / " + root.si.memTotalGb.toFixed(1) + " GB"
                    customColor: Colors.tertiary
                }
                Rectangle {
                    y: 17.4
                    width: parent.width
                    height: 22.6
                    radius: 4
                    color: "transparent"
                    border.width: 1.5
                    border.color: Colors.tertiary
                    Rectangle {
                        x: 2.4; y: 2.6
                        width: Math.max(0, (parent.width - 6) * root.si.memUsage)
                        height: parent.height - 6
                        radius: 2
                        color: Qt.alpha(Colors.tertiary, 0.55)
                        Behavior on width { SpatialAnim {} }
                    }
                }
                Rectangle {
                    y: 45.3
                    width: parent.width
                    height: 15.7
                    radius: 4
                    color: "transparent"
                    border.width: 1.5
                    border.color: Colors.outlineVariant
                    Rectangle {
                        x: 2.4; y: 2.6
                        width: Math.max(0, (parent.width - 6) * root.si.memCacheFrac)
                        height: parent.height - 6
                        radius: 2
                        color: Qt.alpha(Colors.outline, 0.35)
                    }
                }
            }

            Rectangle {
                x: 237.7
                y: 130.6
                width: 163.2
                height: 71.4
                radius: 10
                color: "transparent"
                border.width: 1.5
                border.color: Colors.secondary

                Label { x: 9.5; y: 10.5; content: "GPU"; customColor: Colors.secondary }
                CustomText {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    y: 7
                    content: Math.round(root.si.gpuUsage * 100) + "%"
                    family: root.display
                    renderType: Text.QtRendering
                    size: 15
                    weight: 400
                    customColor: Colors.secondary
                }
                Row {
                    x: 9.5
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 14
                    spacing: 3
                    Repeater {
                        model: 10
                        delegate: Rectangle {
                            required property int index
                            width: (parent.parent.width - 24 - 27) / 10
                            height: 10.5
                            radius: 2
                            color: index < Math.round(root.si.gpuUsage * 10) ? Colors.secondary : "transparent"
                            border.width: 1
                            border.color: index < Math.round(root.si.gpuUsage * 10) ? Colors.secondary : Colors.outlineVariant
                        }
                    }
                }
            }

            Rectangle {
                readonly property bool full: root.si.diskUsage >= 0.85
                readonly property color tint: full ? Colors.error : Colors.primary
                x: 19
                y: 221.2
                width: 150.6
                height: 27.9
                radius: 7
                color: "transparent"
                border.width: 1.5
                border.color: tint

                Row {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8
                    Label { anchors.verticalCenter: parent.verticalCenter; content: "DISK"; customColor: parent.parent.tint }
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 150.6 - 20 - 16 - 38 - 34
                        height: 7
                        radius: 2
                        color: Qt.alpha(parent.parent.tint, 0.2)
                        Rectangle {
                            width: parent.width * root.si.diskUsage
                            height: parent.height
                            radius: 2
                            color: parent.parent.parent.tint
                        }
                    }
                    Label { anchors.verticalCenter: parent.verticalCenter; content: Math.round(root.si.diskUsage * 100) + "%"; customColor: parent.parent.tint }
                }
            }
        }
    }
}
