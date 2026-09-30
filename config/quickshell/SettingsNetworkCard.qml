import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Material network card — the `netcard` row type. Same card language as
// the battery: header with SSID + state pill, two info tiles (IP,
// gateway) read live from nmcli, then two chip groups INSIDE the card —
// BAND (wifi.band: any / 2.4 / 5·6 GHz) and DNS PROVIDER (ipv4.dns +
// ignore-auto-dns). Applying either modifies the active Wi-Fi
// connection and re-joins it (`nmcli con up`) so the change takes
// effect — a ~2 s blip, shown as an "Applying…" pill while the join
// runs; chips are disabled during it. Band values follow NM's
// [a, bg, 6GHz] (the "Auto" chip sends ""), so chips are Auto/2.4/5.
Item {
    id: root

    property var e: null

    property string ipVal: ""
    property string gwVal: ""
    property string ssidVal: ""
    property string bandRaw: ""
    property string dnsRaw: ""
    property string dnsIgnore: ""
    property bool applying: false

    readonly property bool connected: ipVal !== ""
    readonly property var bandCur: {
        if (bandRaw === "" || bandRaw === "any") return "any"
        if (bandRaw === "bg" || bandRaw === "a") return bandRaw
        return null
    }
    readonly property var dnsCur: {
        if (dnsRaw === "") return dnsIgnore === "yes" ? null : "auto"
        if (dnsRaw.startsWith("1.1.1.")) return "cloudflare"
        if (dnsRaw.startsWith("8.8.8.")) return "google"
        if (dnsRaw.startsWith("9.9.9.")) return "quad9"
        return null
    }

    readonly property real extraHeight: Math.max(0, col.implicitHeight - 64)
    height: col.implicitHeight

    // resolves the active Wi-Fi connection name for every write
    readonly property string conFind:
        "con=$(nmcli -t -f NAME,TYPE con show --active | grep '802-11-wireless'"
        + " | head -1 | sed 's/:802-11-wireless.*//')"

    function read() { rd.running = true }
    Component.onCompleted: read()

    Process {
        id: rd
        command: ["bash", "-c",
            "dev=$(nmcli -t -f DEVICE,TYPE dev | grep ':wifi$' | head -1 | cut -d: -f1); "
            + "con=$(nmcli -t -f NAME,TYPE con show --active | grep '802-11-wireless'"
            + " | head -1 | sed 's/:802-11-wireless.*//'); "
            + "ip=$(nmcli -g IP4.ADDRESS dev show \"$dev\" 2>/dev/null | head -1 | cut -d/ -f1); "
            + "gw=$(nmcli -g IP4.GATEWAY dev show \"$dev\" 2>/dev/null | head -1); "
            + "band=$(nmcli -g 802-11-wireless.band con show \"$con\" 2>/dev/null); "
            + "dns=$(nmcli -g ipv4.dns con show \"$con\" 2>/dev/null); "
            + "ign=$(nmcli -g ipv4.ignore-auto-dns con show \"$con\" 2>/dev/null); "
            + "printf '%s|%s|%s|%s|%s|%s\\n' \"$ip\" \"$gw\" \"$band\" \"$dns\" \"$ign\" \"$con\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const f = text.trim().split("|")
                root.ipVal = f[0] || ""
                root.gwVal = f[1] || ""
                root.bandRaw = f[2] || ""
                root.dnsRaw = f[3] || ""
                root.dnsIgnore = f[4] || ""
                root.ssidVal = f[5] || ""
            }
        }
    }

    function run(script) {
        applying = true
        wr.command = ["bash", "-c", script]
        wr.running = true
    }
    Process {
        id: wr
        onExited: {
            root.applying = false
            root.read()
        }
    }

    function setBand(v) {
        const arg = v === "any" ? '""' : "'" + v + "'"
        run(conFind + '; nmcli con modify "$con" wifi.band ' + arg
            + ' && nmcli con up "$con" >/dev/null 2>&1')
    }
    function setDns(v) {
        let mods
        if (v === "cloudflare")
            mods = 'ipv4.dns "1.1.1.1 1.0.0.1" ipv4.ignore-auto-dns yes'
        else if (v === "google")
            mods = 'ipv4.dns "8.8.8.8 8.8.4.4" ipv4.ignore-auto-dns yes'
        else if (v === "quad9")
            mods = 'ipv4.dns "9.9.9.9 149.112.112.112" ipv4.ignore-auto-dns yes'
        else
            mods = 'ipv4.dns "" ipv4.ignore-auto-dns no'
        run(conFind + '; nmcli con modify "$con" ' + mods
            + ' && nmcli con up "$con" >/dev/null 2>&1')
    }

    // one chip look for both groups; the delegate closes over the right
    // setter/selected via the two Components below
    Column {
        id: col
        width: parent.width
        spacing: 10

        Item { width: 1; height: 50 }   // clears the row's label block

        Rectangle {
            id: card
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
                anchors.margins: 14
                spacing: 12

                // header — SSID left, state pill right (anchored, no Row
                // spacer tricks), "Applying…" while the join runs
                Item {
                    width: cardCol.width
                    height: 24

                    Rectangle {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7
                        height: 7
                        radius: 3.5
                        color: root.connected ? Services.Colors.accent : Services.Colors.critical
                    }
                    Text {
                        font.family: Services.Fonts.family
                        id: ssidText
                        anchors.left: parent.left
                        anchors.leftMargin: 15
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(60, parent.width - 150)
                        text: root.ssidVal !== "" ? root.ssidVal : "Not connected"
                        font.pixelSize: 14
                        font.bold: true
                        color: root.connected ? Services.Colors.text : Services.Colors.textMuted
                        elide: Text.ElideRight
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: root.applying
                        width: applyTxt.implicitWidth + 20
                        height: 22
                        radius: 11
                        color: Services.Colors.surfaceAlt
                        Text {
                            font.family: Services.Fonts.family
                            id: applyTxt
                            anchors.centerIn: parent
                            text: "Applying…"
                            font.pixelSize: 11
                            font.bold: true
                            color: Services.Colors.accent
                        }
                    }
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !root.applying
                        width: stateTxt.implicitWidth + 20
                        height: 22
                        radius: 11
                        color: Services.Colors.surfaceAlt
                        Text {
                            font.family: Services.Fonts.family
                            id: stateTxt
                            anchors.centerIn: parent
                            text: root.connected ? "Connected" : "Offline"
                            font.pixelSize: 11
                            font.bold: true
                            color: root.connected ? Services.Colors.accent : Services.Colors.critical
                        }
                    }
                }

                // info tiles — IP + gateway
                Row {
                    width: cardCol.width
                    spacing: 8

                    Repeater {
                        model: [
                            { cap: "IP ADDRESS", val: root.ipVal !== "" ? root.ipVal : "—" },
                            { cap: "GATEWAY",    val: root.gwVal !== "" ? root.gwVal : "—" }
                        ]

                        delegate: Item {
                            width: (cardCol.width - 8) / 2
                            height: 46

                            Rectangle {
                                anchors.fill: parent
                                radius: 10
                                color: Services.Colors.surfaceAlt
                            }
                            Column {
                                anchors.left: parent.left
                                anchors.leftMargin: 10
                                anchors.right: parent.right
                                anchors.rightMargin: 10
                                anchors.top: parent.top
                                anchors.topMargin: 7
                                spacing: 3

                                Text {
                                    font.family: Services.Fonts.family
                                    text: modelData.cap
                                    font.pixelSize: 9
                                    font.bold: true
                                    font.letterSpacing: 1.2
                                    color: Services.Colors.textMuted
                                }
                                Text {
                                    font.family: Services.Fonts.family
                                    text: modelData.val
                                    font.pixelSize: 13
                                    font.bold: true
                                    color: Services.Colors.text
                                    elide: Text.ElideRight
                                    width: parent.width - 4
                                }
                            }
                        }
                    }
                }

                // band chips
                Column {
                    width: cardCol.width
                    spacing: 6

                    Text {
                        font.family: Services.Fonts.family
                        text: "BAND"
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.2
                        color: Services.Colors.textMuted
                    }
                    Flow {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "Auto", value: "any" },
                                { label: "2.4 GHz", value: "bg" },
                                { label: "5 GHz", value: "a" }
                            ]
                            delegate: bandChip
                        }
                    }
                }

                // dns chips
                Column {
                    width: cardCol.width
                    spacing: 6

                    Text {
                        font.family: Services.Fonts.family
                        text: "DNS PROVIDER"
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.2
                        color: Services.Colors.textMuted
                    }
                    Flow {
                        width: parent.width
                        spacing: 6

                        Repeater {
                            model: [
                                { label: "Auto (router)", value: "auto" },
                                { label: "Cloudflare", value: "cloudflare" },
                                { label: "Google", value: "google" },
                                { label: "Quad9", value: "quad9" }
                            ]
                            delegate: dnsChip
                        }
                    }
                }
            }
        }
    }

    Component {
        id: bandChip
        Rectangle {
            readonly property bool selected:
                root.bandCur !== null
                && String(modelData.value) === String(root.bandCur)
            height: 28
            radius: 14
            width: bandChipLabel.width + 26
            color: selected ? Services.Colors.accent : Services.Colors.surface

            Text {
                font.family: Services.Fonts.family
                id: bandChipLabel
                anchors.centerIn: parent
                text: modelData.label
                font.pixelSize: 12
                font.bold: selected
                color: parent.selected ? Services.Colors.background : Services.Colors.textMuted
            }
            MouseArea {
                anchors.fill: parent
                enabled: !root.applying
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setBand(modelData.value)
            }
        }
    }

    Component {
        id: dnsChip
        Rectangle {
            readonly property bool selected:
                root.dnsCur !== null
                && String(modelData.value) === String(root.dnsCur)
            height: 28
            radius: 14
            width: dnsChipLabel.width + 26
            color: selected ? Services.Colors.accent : Services.Colors.surface

            Text {
                font.family: Services.Fonts.family
                id: dnsChipLabel
                anchors.centerIn: parent
                text: modelData.label
                font.pixelSize: 12
                font.bold: selected
                color: parent.selected ? Services.Colors.background : Services.Colors.textMuted
            }
            MouseArea {
                anchors.fill: parent
                enabled: !root.applying
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setDns(modelData.value)
            }
        }
    }
}
