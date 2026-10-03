import QtQuick
import "./services" as Services

// The `btlist` row type — the Devices list on the Bluetooth page.
// Mirrors omasettings' BluetoothSection: three groups (connected /
// paired / nearby) instead of one list you have to infer a sort order
// from, with pair / connect / disconnect / trust / forget actions and
// battery on the row that has it.
//
// Discovery is a mode BlueZ holds, not a one-shot query, so this card
// holds adapter.discovering while it is alive and the settings window
// is on the Bluetooth page — and the combined predicate (shared with
// ControlCenterAdvanced) keeps the control center's own device panel
// from stomping the flag.
Item {
    id: root

    property var e: null

    readonly property real extraHeight: Math.max(0, col.implicitHeight - 64)
    height: col.implicitHeight

    readonly property bool wantScan:
        Services.Bluetooth.powered
        && (Services.ControlCenter.advancedPanel === "bluetooth"
            || (Services.SettingsApp.open && Services.SettingsApp.page === "bluetooth"))

    function syncScan() { Services.Bluetooth.scan(root.wantScan) }

    Component.onCompleted: syncScan()
    onWantScanChanged: syncScan()
    Component.onDestruction: Services.Bluetooth.scan(false)

    readonly property var devs: Services.Bluetooth.devices

    function where(test) {
        const out = []
        for (let i = 0; i < devs.length; i++)
            if (test(devs[i])) out.push(devs[i])
        return out
    }
    readonly property var connectedDevs:
        where(d => d.connected === true)
    readonly property var pairedDevs:
        where(d => d.paired === true && d.connected !== true)
    readonly property var nearbyDevs:
        where(d => d.paired !== true)

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
                spacing: 8

                // header — section caps left, live status right
                Item {
                    width: cardCol.width
                    height: 16

                    Text {
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Services.Fonts.family
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.2
                        color: Services.Colors.textMuted
                        text: "DEVICES"
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Services.Fonts.family
                        font.pixelSize: 11
                        color: Services.Colors.textMuted
                        text: !Services.Bluetooth.adapter ? "No adapter"
                            : !Services.Bluetooth.powered ? "Off"
                            : Services.Bluetooth.discovering ? "Searching…"
                            : root.devs.length + " known"
                    }
                }

                Rectangle { width: cardCol.width; height: 1; color: Services.Colors.low }

                // ---- the three groups ------------------------------
                Column {
                    width: cardCol.width
                    spacing: 6

                    Text {
                        visible: root.connectedDevs.length > 0
                        font.family: Services.Fonts.family
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.2
                        color: Services.Colors.accent
                        text: "CONNECTED"
                    }
                    Repeater {
                        model: root.connectedDevs
                        delegate: devRow
                    }

                    Text {
                        visible: root.pairedDevs.length > 0
                        font.family: Services.Fonts.family
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.2
                        color: Services.Colors.textMuted
                        text: "PAIRED"
                    }
                    Repeater {
                        model: root.pairedDevs
                        delegate: devRow
                    }

                    Text {
                        visible: root.nearbyDevs.length > 0
                        font.family: Services.Fonts.family
                        font.pixelSize: 9
                        font.bold: true
                        font.letterSpacing: 1.2
                        color: Services.Colors.textMuted
                        text: "NEARBY"
                    }
                    Repeater {
                        model: root.nearbyDevs
                        delegate: devRow
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        visible: root.devs.length === 0
                        font.family: Services.Fonts.family
                        font.pixelSize: 11
                        color: Services.Colors.textMuted
                        text: !Services.Bluetooth.adapter ? "No bluetooth adapter found"
                            : !Services.Bluetooth.powered ? "Adapter off — flip the switch above"
                            : Services.Bluetooth.discovering ? "Looking for devices…"
                            : "No devices"
                    }
                }
            }
        }
    }

    // one row shape for all three groups — they differ only in what
    // they hold, never in how they act
    Component {
        id: devRow

        Rectangle {
            id: dev
            required property var modelData
            width: cardCol.width
            height: 48
            radius: 8
            color: dev.modelData.connected
                ? Qt.rgba(Services.Colors.accent.r, Services.Colors.accent.g,
                          Services.Colors.accent.b, 0.14)
                : Services.Colors.surfaceAlt

            // left: name + state / battery / trust meta
            Column {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                Text {
                    font.family: Services.Fonts.family
                    font.pixelSize: 12
                    font.bold: dev.modelData.connected
                    color: dev.modelData.connected ? Services.Colors.accent
                                                 : Services.Colors.text
                    text: dev.modelData.name
                    elide: Text.ElideRight
                    width: Math.min(implicitWidth, 170)
                }
                Row {
                    spacing: 6
                    Text {
                        font.family: Services.Fonts.family
                        font.pixelSize: 10
                        color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                       Services.Colors.text.b, 0.5)
                        text: dev.modelData.pairing ? "Pairing…"
                            : dev.modelData.connected ? "Connected"
                            : dev.modelData.paired ? "Paired" : "Not paired"
                    }
                    Text {
                        visible: dev.modelData.batteryAvailable
                        font.family: Services.Fonts.family
                        font.pixelSize: 10
                        color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                       Services.Colors.text.b, 0.5)
                        text: "· " + Math.round(dev.modelData.battery * 100) + "%"
                    }
                    Text {
                        visible: dev.modelData.paired && dev.modelData.trusted
                        font.family: Services.Fonts.family
                        font.pixelSize: 10
                        color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                       Services.Colors.text.b, 0.5)
                        text: "· trusted"
                    }
                }
            }

            // right: actions
            Row {
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10

                Text {
                    visible: !dev.modelData.paired && !dev.modelData.pairing
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    font.bold: true
                    color: Services.Colors.accent
                    text: "Pair"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Bluetooth.pairDevice(dev.modelData)
                    }
                }
                Text {
                    visible: dev.modelData.pairing
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    color: Services.Colors.text
                    text: "Cancel"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: dev.modelData.cancelPair()
                    }
                }
                Text {
                    visible: dev.modelData.paired && !dev.modelData.connected
                             && !dev.modelData.pairing
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    font.bold: true
                    color: Services.Colors.accent
                    text: "Connect"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Bluetooth.connectDevice(dev.modelData)
                    }
                }
                Text {
                    visible: dev.modelData.connected
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    color: Services.Colors.text
                    text: "Disconnect"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Bluetooth.disconnectDevice(dev.modelData)
                    }
                }
                Text {
                    visible: dev.modelData.paired && !dev.modelData.pairing
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    color: Services.Colors.text
                    text: dev.modelData.trusted ? "Untrust" : "Trust"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        // `trusted` is a writable property on BluetoothDevice
                        onClicked: dev.modelData.trusted = !dev.modelData.trusted
                    }
                }
                Text {
                    visible: dev.modelData.paired && !dev.modelData.pairing
                    font.family: Services.Fonts.family
                    font.pixelSize: 11
                    color: Services.Colors.critical
                    text: "Forget"
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: Services.Bluetooth.forgetDevice(dev.modelData)
                    }
                }
            }
        }
    }
}
