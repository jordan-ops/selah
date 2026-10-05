// Ported from Nebula's Widgets/WorldClockWidget.qml (GPL-3.0) — qs.modules imports
// dropped: its deps (SettingsConfig, GlobalStates, Colors, the kit,
// WidgetSizes/WidgetLayout, the service adapters) are siblings in widgets/.
import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Layouts
import "shapes/" as MaterialShapes
import "shapes/material-shapes.js" as MaterialShapeFn
import "shapes/shape-library.js" as ShapeLibrary

WidgetHost {
    id: root
    configKey: "worldClock"
    tile: Qt.size(WidgetSizes.span(3), WidgetSizes.span(1.5))
    defaultPos: Qt.point(880, 440)

    readonly property var defaultZones: [
        { label: "Local", tz: "" },
        { label: "Tokyo", tz: "Asia/Tokyo" },
        { label: "London", tz: "Europe/London" }
    ]
    readonly property var zones: {
        const z = SettingsConfig.widgets.worldClockZones
        return (Array.isArray(z) && z.length > 0) ? z.slice(0, 3) : root.defaultZones
    }
    readonly property var namedZones: root.zones.map(z => z.tz).filter(tz => !!tz)

    property var offsets: ({})
    readonly property string shapeLock: SettingsConfig.widgets.worldClockShapeLock ?? ""

    function setZone(index, patch) {
        const zones = root.zones.map(z => Object.assign({}, z))
        while (zones.length < 3) zones.push({ label: "", tz: "" })
        zones[index] = Object.assign(zones[index], patch)
        SettingsConfig.widgets = Object.assign({}, SettingsConfig.widgets, { worldClockZones: zones })
    }

    optionsComponent: Component {
        ColumnLayout {
            spacing: 6

            ShapePicker {
                Layout.fillWidth: true
                Layout.bottomMargin: 8
                selected: root.shapeLock
                autoHint: "Sun by day, ghost at night"
                onPicked: name => SettingsConfig.widgets = Object.assign({}, SettingsConfig.widgets, { worldClockShapeLock: name })
            }

            Repeater {
                model: 3

                delegate: RowLayout {
                    id: zoneRow
                    required property int index
                    readonly property var zone: root.zones[zoneRow.index] ?? { label: "", tz: "" }

                    Layout.fillWidth: true
                    spacing: 6

                    Rectangle {
                        implicitWidth: 28
                        implicitHeight: 28
                        radius: 14
                        color: Colors.primaryContainer

                        CustomText {
                            anchors.centerIn: parent
                            content: String(zoneRow.index + 1)
                            size: 12
                            weight: 700
                            customColor: Colors.primaryContainerText
                        }
                    }

                    OptionField {
                        Layout.preferredWidth: 96
                        placeholder: "Label"
                        text: zoneRow.zone.label ?? ""
                        onCommitted: value => root.setZone(zoneRow.index, { label: value })
                    }

                    OptionField {
                        Layout.fillWidth: true
                        placeholder: zoneRow.index === 0 ? "Local time" : "Area/City"
                        text: zoneRow.zone.tz ?? ""
                        onCommitted: value => root.setZone(zoneRow.index, { tz: value })
                    }
                }
            }

            CustomText {
                Layout.fillWidth: true
                Layout.topMargin: 2
                wrapMode: Text.WordWrap
                content: "Zones use IANA names such as Asia/Tokyo or Europe/London. Leave one empty for your local time."
                size: 11
                customColor: Colors.outline
            }
        }
    }

    function refreshOffsets() {
        if (root.namedZones.length === 0) return
        offsetProc.command = ["sh", "-c", "for z in \"$@\"; do TZ=\"$z\" date +%z; done", "sh"]
            .concat(root.namedZones)
        offsetProc.running = true
    }

    onNamedZonesChanged: root.refreshOffsets()

    Timer {
        interval: 3600000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshOffsets()
    }

    Process {
        id: offsetProc
        command: []
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                const out = {}
                for (let i = 0; i < lines.length && i < root.namedZones.length; i++) {
                    const m = lines[i].trim().match(/^([+-])(\d{2})(\d{2})$/)
                    if (!m) continue
                    out[root.namedZones[i]] = (m[1] === "-" ? -1 : 1) * (parseInt(m[2], 10) * 60 + parseInt(m[3], 10))
                }
                root.offsets = out
            }
        }
    }

    function timeFor(tz) {
        const now = new Date()
        if (!tz) return { h: now.getHours(), m: now.getMinutes() }
        const off = root.offsets[tz]
        if (off === undefined) return null
        const shifted = new Date(now.getTime() + off * 60000)
        return { h: shifted.getUTCHours(), m: shifted.getUTCMinutes() }
    }

    WidgetCard {
        anchors.fill: parent

        RowLayout {
            anchors.fill: parent
            anchors.margins: parent.pad
            spacing: 0

            Repeater {
                model: root.zones

                delegate: ColumnLayout {
                    id: city
                    required property var modelData
                    readonly property var time: {
                        ServiceClock.minute
                        root.offsets
                        return root.timeFor(modelData.tz)
                    }
                    readonly property bool day: city.time !== null && city.time.h >= 6 && city.time.h < 18

                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 6

                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        MaterialShapes.ShapeCanvas {
                            id: badge
                            anchors.centerIn: parent
                            width: Math.min(parent.width, parent.height)
                            height: width
                            roundedPolygon: root.shapeLock !== "" ? (ShapeLibrary.get(root.shapeLock) ?? MaterialShapeFn.getCircle())
                                : city.day ? MaterialShapeFn.getSunny() : MaterialShapeFn.getGhostish()
                            color: city.day ? Colors.primaryContainer : Colors.surfaceContainerHighest
                        }

                        CustomText {
                            anchors.centerIn: parent
                            content: city.time
                                ? String(city.time.h).padStart(2, "0") + ":" + String(city.time.m).padStart(2, "0")
                                : "--:--"
                            size: 15
                            weight: 700
                            customColor: city.day ? Colors.primaryContainerText : Colors.surfaceText
                        }
                    }

                    CustomText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.maximumWidth: parent.width
                        content: city.modelData.label
                        size: 12
                        customColor: Colors.outline
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }
}
