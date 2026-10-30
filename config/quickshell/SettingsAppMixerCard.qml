import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "./services" as Services

// Per-app output routing — the `appmixer` row type, Audio page. Every
// playing stream (pactl sink-inputs) becomes a row: the app's icon and
// name plus a sink dropdown that MOVES that one stream
// (pactl move-sink-input) — the pavucontrol Playback tab, native here.
//
// Live class, no Apply/Revert: routing has no baseline to revert to and
// a mixer that makes you press Apply isn't a mixer (same class as the
// cmdswitch/cmdslider rows). Streams are polled every 2 s while the
// audio page shows this card — apps appear as they start playing and
// vanish when they stop. The poll skips identical payloads so an OPEN
// dropdown isn't torn down every tick.
Item {
    id: root

    property var e: null

    // [{ index, sink, app, icon, media }] — rebuilt from pactl each tick
    property var streams: []
    // [{ index, name, description }] — index→sink map, slow poll: the
    // device list rarely moves while streams come and go constantly
    property var sinks: []

    function sinkNameFor(idx) {
        const hit = sinks.find(s => s.index === idx)
        return hit ? hit.name : ""
    }

    height: col.implicitHeight
    readonly property real extraHeight: col.implicitHeight - 64

    Timer {
        interval: 2000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: {
            streamsProc.running = false
            streamsProc.running = true
        }
    }
    Timer {
        interval: 10000; repeat: true; running: true; triggeredOnStart: true
        onTriggered: {
            sinksProc.running = false
            sinksProc.running = true
        }
    }

    Process {
        id: streamsProc
        command: ["pactl", "-f", "json", "list", "sink-inputs"]
        stdout: StdioCollector {
            onStreamFinished: {
                const out = []
                try {
                    JSON.parse(text).forEach(si => {
                        const p = si.properties || {}
                        out.push({
                            index: si.index,
                            sink: si.sink,
                            app: p["application.name"] || p["application.process.binary"] || "Unknown app",
                            icon: p["application.icon_name"] || "",
                            media: p["media.name"] || ""
                        })
                    })
                } catch (err) {
                    console.log("appmixer: pactl json parse failed", err)
                }
                // identity compare — a steady state must not recreate the
                // delegates (and close an open dropdown) every 2 s
                if (JSON.stringify(out) !== JSON.stringify(root.streams))
                    root.streams = out
            }
        }
    }

    Process {
        id: sinksProc
        command: ["bash", "-c", "pactl -f json list sinks; echo '---SPLIT---'; pactl get-default-sink"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("---SPLIT---")
                const out = []
                const def = (parts[1] || "").trim()
                try {
                    JSON.parse(parts[0]).forEach(s => out.push({
                        index: s.index,
                        name: s.name,
                        description: s.description || s.name,
                        // the default gets a marker so "where does this
                        // go by default" is readable at a glance
                        isDefault: s.name === def
                    }))
                } catch (err) {
                    console.log("appmixer: sinks parse failed", err)
                }
                root.sinks = out
            }
        }
    }

    Column {
        id: col
        width: parent.width
        spacing: 8

        Rectangle {
            width: col.width
            height: cardCol.implicitHeight + 28
            radius: 16
            color: Services.Colors.surface
            border.color: Services.Colors.low
            border.width: 1

            Column {
                id: cardCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.topMargin: 14
                spacing: 6

                Text {
                    visible: root.streams.length === 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    color: Services.Colors.textMuted
                    text: "Nothing is playing — apps appear here live as they start making sound"
                }

                Repeater {
                    model: root.streams

                    delegate: Item {
                        id: row
                        required property int index
                        required property var modelData

                        width: cardCol.width
                        height: 34
                        // an open dropdown's panel lives inside this row —
                        // lift it above the delegates that render after
                        // this card, or the list hides behind them
                        z: dd.open ? 10 : 0

                        IconImage {
                            id: appIcon
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            implicitSize: 20
                            source: Quickshell.iconPath(row.modelData.icon || "",
                                                       "audio-volume-high-symbolic")
                        }

                        Column {
                            anchors.left: appIcon.right
                            anchors.leftMargin: 10
                            anchors.right: dd.left
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 1

                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                font.family: Services.Fonts.family
                                font.pixelSize: 13
                                font.bold: true
                                color: Services.Colors.text
                                text: row.modelData.app
                            }
                            Text {
                                width: parent.width
                                elide: Text.ElideRight
                                visible: row.modelData.media !== ""
                                font.family: Services.Fonts.family
                                font.pixelSize: 10
                                color: Services.Colors.textMuted
                                text: row.modelData.media
                            }
                        }

                        SettingsDropdownRow {
                            id: dd
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            e: ({ source: "sinkinput" })
                            streamIdx: row.modelData.index
                            current: root.sinkNameFor(row.modelData.sink)
                        }
                    }
                }
            }
        }
    }
}
