import QtQuick
import Quickshell.Networking
import "./services" as Services

// The "advanced" half of the hybrid picker approach: full device lists with
// real actions (pair, trust, forget), given actual room to breathe instead
// of being crammed into a tile-sized popover. Opened via
// Services.ControlCenter.openAdvanced("network" | "bluetooth"),
// wrapped in its own PopupWindow in Bar.qml, docked beside the main panel.
Rectangle {
    id: root
    width: 260
    // Audio typically has 2-4 sinks — no reason to reserve the full 380px
    // network/bluetooth need for potentially long device lists. Bar.qml's
    // sizer reads this height directly (same "content decides size, window
    // follows" idea as the pill's notif/launcher modes).
    readonly property bool isAudio: Services.ControlCenter.advancedPanel === "audio"
    height: isAudio ? Math.min(380, 56 + Math.max(1, Services.Volume.sinks.length) * 50) : 380
    radius: 18
    color: Services.Colors.background

    readonly property bool isNetwork: Services.ControlCenter.advancedPanel === "network"
    readonly property bool isBluetooth: Services.ControlCenter.advancedPanel === "bluetooth"

    // Only scan while the network panel is actually the one showing — same
    // idea as a Waybar wifi module only running `nmcli dev wifi list` while
    // its menu is open, not on every poll tick. This used to be triggered by
    // ControlCenterPanel.qml's quick popover; that's gone now, so this is
    // the only place left that needs to own it.
    Connections {
        target: Services.ControlCenter
        function onAdvancedPanelChanged() {
            Services.Network.scan(Services.ControlCenter.advancedPanel === "network")
        }
    }

    Column {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 10

        Row {
            width: parent.width
            Text {
                font.family: Services.Fonts.family
                text: root.isNetwork ? "Wifi Networks" : root.isBluetooth ? "Bluetooth Devices" : "Output Devices"
                color: Services.Colors.text
                font.pixelSize: 14
                font.bold: true
            }
            Item { width: parent.width - 170; height: 1 }
            Text {
                font.family: Services.Fonts.family
                text: "✕"
                font.pixelSize: 13
                color: Services.Colors.text
                MouseArea {
                    anchors.fill: parent
                    onClicked: Services.ControlCenter.closeAdvanced()
                }
            }
        }

        // ---------------- AUDIO: full output device list ----------------
        // Same Services.Volume API the old quick popover in
        // ControlCenterPanel.qml used (sinks / isCurrentSink / setSink) —
        // this is that same list, just given a full window instead of a
        // 200px floating overlay.
        ListView {
            visible: root.isAudio
            width: parent.width
            height: parent.height - 40
            clip: true
            spacing: 6
            model: root.isAudio ? Services.Volume.sinks : []

            Text {
                font.family: Services.Fonts.family
                anchors.centerIn: parent
                visible: root.isAudio && Services.Volume.sinks.length === 0
                text: "No devices found"
                color: Services.Colors.text_muted
                font.pixelSize: 12
            }

            delegate: Rectangle {
                required property var modelData
                property bool isActive: Services.Volume.isCurrentSink(modelData)
                width: parent.width
                height: 44
                radius: 8
                color: isActive
                    ? Qt.rgba(Services.Colors.accent.r, Services.Colors.accent.g, Services.Colors.accent.b, 0.14)
                    : Services.Colors.surface

                Text {
                    font.family: Services.Fonts.family
                    anchors {
                        left: parent.left; leftMargin: 10
                        right: parent.right; rightMargin: 10
                        verticalCenter: parent.verticalCenter
                    }
                    elide: Text.ElideRight
                    text: modelData.description !== "" ? modelData.description : modelData.name
                    font.pixelSize: 12
                    color: isActive ? Services.Colors.accent : Services.Colors.text
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: Services.Volume.setSink(modelData)
                }
            }
        }

        // ---------------- NETWORK: full list, connect/forget/password ----
        ListView {
            visible: root.isNetwork
            width: parent.width
            height: parent.height - 40
            clip: true
            spacing: 6
            model: root.isNetwork ? Services.Network.networks : []

            Text {
                font.family: Services.Fonts.family
                anchors.centerIn: parent
                visible: root.isNetwork && Services.Network.networks.length === 0
                text: "Scanning…"
                color: Services.Colors.text_muted
                font.pixelSize: 12
            }

            delegate: Column {
                id: netAdvRow
                required property var modelData
                property bool needsPassword: false
                property string errorText: ""
                width: parent.width
                spacing: 4

                Connections {
                    target: netAdvRow.modelData
                    function onConnectionFailed(reason) {
                        if (reason === ConnectionFailReason.NoSecrets) netAdvRow.needsPassword = true
                        else netAdvRow.errorText = "Connection failed"
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 44
                    radius: 8
                    color: modelData.connected
                        ? Qt.rgba(Services.Colors.accent.r, Services.Colors.accent.g, Services.Colors.accent.b, 0.14)
                        : Services.Colors.surface

                    Column {
                        anchors { left: parent.left; leftMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 1
                        Text {
                            font.family: Services.Fonts.family
                            text: modelData.name
                            font.pixelSize: 12
                            color: modelData.connected ? Services.Colors.accent : Services.Colors.text
                        }
                        Row {
                            spacing: 6
                            Text {
                                font.family: Services.Fonts.family
                                text: modelData.connected ? "Connected" : modelData.known ? "Saved" : "Not saved"
                                font.pixelSize: 10
                                color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.5)
                            }
                        }
                    }

                    Row {
                        anchors { right: parent.right; rightMargin: 10; verticalCenter: parent.verticalCenter }
                        spacing: 10

                        Text {
                            font.family: Services.Fonts.family
                            visible: !modelData.connected
                            text: "Connect"
                            font.pixelSize: 11
                            color: Services.Colors.accent
                            MouseArea { anchors.fill: parent; onClicked: { netAdvRow.errorText = ""; Services.Network.connectToNetwork(modelData) } }
                        }
                        Text {
                            font.family: Services.Fonts.family
                            visible: modelData.connected
                            text: "Disconnect"
                            font.pixelSize: 11
                            color: Services.Colors.text
                            MouseArea { anchors.fill: parent; onClicked: modelData.disconnect() }
                        }
                        Text {
                            font.family: Services.Fonts.family
                            visible: modelData.known
                            text: "Forget"
                            font.pixelSize: 11
                            color: "#e06060"
                            MouseArea { anchors.fill: parent; onClicked: modelData.forget() }
                        }
                    }
                }

                Row {
                    visible: netAdvRow.needsPassword
                    width: parent.width
                    spacing: 6
                    Rectangle {
                        width: parent.width - 40
                        height: 26
                        radius: 6
                        color: Services.Colors.surface
                        border.color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.15)
                        border.width: 1
                        TextInput {
                            font.family: Services.Fonts.family
                            id: netAdvPw
                            anchors { fill: parent; margins: 6 }
                            echoMode: TextInput.Password
                            font.pixelSize: 11
                            color: Services.Colors.text
                            clip: true
                            onAccepted: {
                                netAdvRow.needsPassword = false
                                Services.Network.connectToNetworkWithPsk(netAdvRow.modelData, netAdvPw.text)
                            }
                        }
                    }
                    Text {
                        font.family: Services.Fonts.family
                        text: "Go"
                        font.pixelSize: 11
                        color: Services.Colors.accent
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                netAdvRow.needsPassword = false
                                Services.Network.connectToNetworkWithPsk(netAdvRow.modelData, netAdvPw.text)
                            }
                        }
                    }
                }

                Text {
                    font.family: Services.Fonts.family
                    visible: netAdvRow.errorText !== ""
                    text: netAdvRow.errorText
                    font.pixelSize: 10
                    color: "#e06060"
                }
            }
        }

        // ---------------- BLUETOOTH: full list, connect/pair/trust/forget --
        ListView {
            visible: root.isBluetooth
            width: parent.width
            height: parent.height - 40
            clip: true
            spacing: 6
            model: root.isBluetooth ? Services.Bluetooth.devices : []

            Text {
                font.family: Services.Fonts.family
                anchors.centerIn: parent
                visible: root.isBluetooth && Services.Bluetooth.devices.length === 0
                text: "No devices"
                color: Services.Colors.text_muted
                font.pixelSize: 12
            }

            delegate: Rectangle {
                required property var modelData
                width: parent.width
                height: 56
                radius: 8
                color: modelData.connected
                    ? Qt.rgba(Services.Colors.accent.r, Services.Colors.accent.g, Services.Colors.accent.b, 0.14)
                    : Services.Colors.surface

                Column {
                    anchors { left: parent.left; leftMargin: 10; top: parent.top; topMargin: 8 }
                    spacing: 1
                    Text {
                        font.family: Services.Fonts.family
                        text: modelData.name
                        font.pixelSize: 12
                        color: modelData.connected ? Services.Colors.accent : Services.Colors.text
                    }
                    Row {
                        spacing: 6
                        Text {
                            font.family: Services.Fonts.family
                            text: modelData.connected ? "Connected" : modelData.paired ? "Paired" : "Not paired"
                            font.pixelSize: 10
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.5)
                        }
                        Text {
                            font.family: Services.Fonts.family
                            visible: modelData.batteryAvailable
                            text: "· " + Math.round(modelData.battery * 100) + "%"
                            font.pixelSize: 10
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.5)
                        }
                        Text {
                            font.family: Services.Fonts.family
                            visible: modelData.trusted
                            text: "· trusted"
                            font.pixelSize: 10
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.5)
                        }
                    }
                }

                Row {
                    anchors { left: parent.left; leftMargin: 10; bottom: parent.bottom; bottomMargin: 6 }
                    spacing: 10

                    Text {
                        font.family: Services.Fonts.family
                        visible: !modelData.paired
                        text: "Pair"
                        font.pixelSize: 11
                        color: Services.Colors.accent
                        MouseArea { anchors.fill: parent; onClicked: Services.Bluetooth.pairDevice(modelData) }
                    }
                    Text {
                        font.family: Services.Fonts.family
                        visible: modelData.paired && !modelData.connected
                        text: "Connect"
                        font.pixelSize: 11
                        color: Services.Colors.accent
                        MouseArea { anchors.fill: parent; onClicked: Services.Bluetooth.connectDevice(modelData) }
                    }
                    Text {
                        font.family: Services.Fonts.family
                        visible: modelData.connected
                        text: "Disconnect"
                        font.pixelSize: 11
                        color: Services.Colors.text
                        MouseArea { anchors.fill: parent; onClicked: Services.Bluetooth.disconnectDevice(modelData) }
                    }
                    Text {
                        font.family: Services.Fonts.family
                        visible: modelData.paired
                        text: modelData.trusted ? "Untrust" : "Trust"
                        font.pixelSize: 11
                        color: Services.Colors.text
                        // `trusted` is a writable property per BluetoothDevice's
                        // docs — no separate trust()/untrust() function needed.
                        MouseArea { anchors.fill: parent; onClicked: modelData.trusted = !modelData.trusted }
                    }
                    Text {
                        font.family: Services.Fonts.family
                        visible: modelData.paired
                        text: "Forget"
                        font.pixelSize: 11
                        color: "#e06060"
                        MouseArea { anchors.fill: parent; onClicked: Services.Bluetooth.forgetDevice(modelData) }
                    }
                }
            }
        }
    }
}
