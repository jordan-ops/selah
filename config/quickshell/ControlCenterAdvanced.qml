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

    // Esc closes the WHOLE control center (this popup + the pill) — same
    // contract as Escape on the plain panel. Keys reach this handler
    // because Bar.qml gives the popup content Qt active focus when it
    // maps (onVisibleChanged → forceActiveFocus), and the password field
    // bubbles anything it doesn't accept up the parent chain to here.
    // The popup lives in its own window, so the pill's Keys handler can
    // never see these events — it needs its own, or Escape dead-ends.
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Escape) {
            Services.ControlCenter.close()
            event.accepted = true
        }
    }

    // Password-prompt state lives on the PANEL, not the row delegate. The
    // model refreshes while scanning and ListViews reuse/destroy delegates
    // on model churn — a delegate-owned flag was wiped right after
    // connectionFailed fired, so the prompt never showed (or showed under
    // a recycled row) even though the signal arrived. Keyed by the Network
    // object; cleared when the panel closes/switches or on submit.
    property var passwordTarget: null

    function requestPassword(network) {
        root.passwordTarget = network
        // The list viewport is fixed-height and clipped — a row near the
        // bottom would put the prompt below the fold, invisible. Bring it in.
        const i = Services.Network.networks.indexOf(network)
        if (i >= 0)
            Qt.callLater(() => netAdvList.positionViewAtIndex(i, ListView.Contain))
    }

    // Re-seat the password row if scan churn/reorder pushes it out of the
    // clipped viewport — positionViewAtIndex at request time races the model.
    Timer {
        interval: 300
        repeat: true
        running: root.passwordTarget !== null && root.isNetwork
        onTriggered: {
            const i = Services.Network.networks.indexOf(root.passwordTarget)
            if (i < 0) return
            const it = netAdvList.itemAtIndex(i)
            if (!it || it.y < netAdvList.contentY
                || it.y + it.height > netAdvList.contentY + netAdvList.height)
                netAdvList.positionViewAtIndex(i, ListView.Contain)
        }
    }

    // Only scan while the network/bluetooth panel is actually the one
    // showing — same idea as a Waybar wifi module only running
    // `nmcli dev wifi list` while its menu is open, not on every poll
    // tick. The settings app's Network/Bluetooth pages hold their own
    // visible lists too, so BOTH owners evaluate this same combined
    // predicate: whoever fires last leaves the flags in the right state
    // and they can never stomp each other.
    Connections {
        target: Services.ControlCenter
        function onAdvancedPanelChanged() {
            const panel = Services.ControlCenter.advancedPanel
            if (panel !== "network") root.passwordTarget = null
            const setNet = Services.SettingsApp.open && Services.SettingsApp.page === "network"
            const setBt = Services.SettingsApp.open && Services.SettingsApp.page === "bluetooth"
            Services.Network.scan(panel === "network" || setNet)
            Services.Bluetooth.scan(panel === "bluetooth" || setBt)
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
                width: parent ? parent.width : 0
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
            id: netAdvList
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
                property string errorText: ""
                // parent is momentarily null while ListView recycles this
                // delegate during scan churn — unguarded parent.width threw
                // "Cannot read property 'width' of null" and broke layout.
                width: parent ? parent.width : 0
                spacing: 4

                Connections {
                    target: netAdvRow.modelData
                    function onConnectionFailed(reason) {
                        if (reason === ConnectionFailReason.NoSecrets)
                            root.requestPassword(netAdvRow.modelData)
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
                    visible: root.passwordTarget === netAdvRow.modelData
                    width: parent.width
                    spacing: 6

                    // The popup window only ever gets keyboard focus from
                    // the HyprlandFocusGrab in Bar.qml, and a field that
                    // appears AFTER that focus settled never receives Qt
                    // active focus on its own — keystrokes went nowhere
                    // (same failure mode as the clipboard search field,
                    // documented in Bar.qml). Grab focus the moment the
                    // row shows up.
                    onVisibleChanged: {
                        if (visible) Qt.callLater(() => netAdvPw.forceActiveFocus())
                    }
                    // Scan churn rebuilds delegates constantly; a Row born
                    // already-visible never fires onVisibleChanged, so the
                    // focus grab below would silently never run and the
                    // field would sit dead (keys went to the bar surface).
                    Component.onCompleted: if (visible)
                        Qt.callLater(() => netAdvPw.forceActiveFocus())

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
                            // kimi default (NetworkRow.qml:159 focus:
                            // root.awaitingPassword) — declarative sibling
                            // of the forceActiveFocus in the Row above.
                            focus: root.passwordTarget === netAdvRow.modelData
                            font.pixelSize: 11
                            color: Services.Colors.text
                            clip: true
                            onAccepted: {
                                root.passwordTarget = null
                                Services.Network.connectToNetworkWithPsk(netAdvRow.modelData, netAdvPw.text)
                            }
                        }
                        // placeholder — TextInput has none, and an empty
                        // dark box gives no affordance that it's a field
                        Text {
                            anchors { fill: parent; margins: 6 }
                            visible: netAdvPw.text === ""
                                && root.passwordTarget === netAdvRow.modelData
                            text: "Password…"
                            font.family: Services.Fonts.family
                            font.pixelSize: 11
                            verticalAlignment: Text.AlignVCenter
                            color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.4)
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
                                root.passwordTarget = null
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
                width: parent ? parent.width : 0
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
