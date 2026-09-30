import QtQuick
import "./services" as Services

// About page — Power-section-style cards instead of flat info rows.
//   · fastfetch details grouped by domain (System / Hardware / Display /
//     Network & battery) and sorted A→Z inside each card
//   · theme/wallpaper selectors live in Appearance as their own cards
//     (moved out of here — one home per selector)
Flickable {
    id: root

    property var ffRows: []
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: width
    contentHeight: col.implicitHeight

    // bucket every fastfetch row by label prefix, then sort inside —
    // deterministic grouping is the "sorting" for free--form labels
    readonly property var groups: {
        const g = { system: [], hardware: [], display: [], network: [], other: [] }
        const rows = ffRows || []
        for (const e of rows) {
            const l = e.label
            if (/^(OS|Host|Kernel|Uptime|Packages|Locale)$/.test(l)) g.system.push(e)
            else if (/^(CPU|GPU|Memory|Swap|Disk)/.test(l)) g.hardware.push(e)
            else if (/^(Display|Window Manager|Theme|Icons|Font|Cursor|Terminal)/.test(l)) g.display.push(e)
            else if (/^(Local IP|Battery)/.test(l)) g.network.push(e)
            else g.other.push(e)
        }
        for (const k in g) g[k].sort((a, b) => a.label.localeCompare(b.label))
        return g
    }

    // one card per non-empty group, selectors last
    readonly property var cards: {
        const defs = [
            { title: "System",             key: "system" },
            { title: "Hardware",           key: "hardware" },
            { title: "Display",            key: "display" },
            { title: "Network & battery",  key: "network" },
            { title: "Other",              key: "other" }
        ]
        return defs.filter(d => groups[d.key].length > 0)
    }

    Column {
        id: col
        width: root.width
        spacing: 12

        // ——————— info cards ———————
        Repeater {
            model: root.cards

            delegate: Rectangle {
                required property var modelData
                readonly property var rows: root.groups[modelData.key]

                width: col.width
                height: infoCol.implicitHeight + 28
                radius: 16
                color: Services.Colors.surface
                border.color: Services.Colors.low
                border.width: 1

                Column {
                    id: infoCol
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 14
                    spacing: 6

                    Item { width: 1; height: 2 }   // optical gap under the title

                    Text {
                        font.family: Services.Fonts.family
                        text: modelData.title
                        font.pixelSize: 13
                        font.bold: true
                        color: Services.Colors.text
                    }

                    Item { width: 1; height: 4 }

                    Repeater {
                        model: rows

                        delegate: Item {
                            required property var modelData
                            width: infoCol.width
                            height: 26

                            Text {
                                font.family: Services.Fonts.family
                                id: lab
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: modelData.label
                                font.pixelSize: 12
                                color: Services.Colors.textMuted
                            }
                            Text {
                                font.family: Services.Fonts.family
                                anchors.left: lab.right
                                anchors.leftMargin: 14
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                elide: Text.ElideRight
                                text: modelData.value
                                font.pixelSize: 12
                                font.bold: true
                                color: Services.Colors.accent
                            }
                        }
                    }
                }
            }
        }

    }
}
