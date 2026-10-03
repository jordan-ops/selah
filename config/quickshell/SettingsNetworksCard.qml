import QtQuick
import Quickshell.Networking
import "./services" as Services

// The `netlist` row type — the Networks list on the Network page.
// Same card language as SettingsNetworkCard (netcard): a labelled card
// under the row's own title, but instead of band/DNS chips it holds the
// live wifi scan list with per-network actions — connect, disconnect,
// forget — and an inline password field when NetworkManager comes back
// with NoSecrets (the recommended Quickshell flow: connect() first, the
// stored-PSK fallback only when it fails).
//
// Scanning follows the same on-screen-only contract as the control
// center's advanced panel: hold Services.Network.scan(true) while this
// card is alive and the settings window is up, hand it back otherwise.
// Both owners evaluate the SAME predicate (see ControlCenterAdvanced)
// so they can't fight over the flag.
Item {
    id: root

    property var e: null

    readonly property real extraHeight: Math.max(0, col.implicitHeight - 64)
    height: col.implicitHeight

    readonly property bool showScan:
        Services.ControlCenter.advancedPanel === "network"
        || (Services.SettingsApp.open && Services.SettingsApp.page === "network")

    function syncScan() { Services.Network.scan(root.showScan) }

    Component.onCompleted: syncScan()
    onShowScanChanged: syncScan()
    Component.onDestruction: Services.Network.scan(root.showScan)

    // Same delegate-recycle guard as ControlCenterAdvanced: netRows below
    // is a fresh array on every signal-strength tick, so the Repeater
    // rebuilds all rows — a delegate-owned needsPassword flag vanished
    // right after connectionFailed(NoSecrets) fired and the prompt never
    // showed. Keyed by the Network object on the card instead.
    property var passwordTarget: null

    // connected first, then saved networks, then strongest signal — the
    // order omasettings grouped its list into, flattened into one sort
    readonly property var netRows: {
        const nets = Services.Network.networks.slice()
        nets.sort((a, b) => {
            if (a.connected !== b.connected) return a.connected ? -1 : 1
            if (a.known !== b.known) return a.known ? -1 : 1
            return (b.signalStrength || 0) - (a.signalStrength || 0)
        })
        return nets
    }

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
                        text: "NETWORKS"
                    }
                    Text {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Services.Fonts.family
                        font.pixelSize: 11
                        color: Services.Colors.textMuted
                        text: !Services.Network.wifiDevice ? "Wi-Fi off"
                            : root.netRows.length === 0 ? "Scanning…"
                            : root.netRows.length + " found"
                    }
                }

                Rectangle { width: cardCol.width; height: 1; color: Services.Colors.low }

                // ---- the scan list ---------------------------------
                Column {
                    width: cardCol.width
                    spacing: 4

                    Repeater {
                        model: root.netRows

                        delegate: Column {
                            id: netCol
                            required property var modelData
                            property string errorText: ""

                            width: cardCol.width
                            spacing: 4

                            Connections {
                                target: netCol.modelData
                                function onConnectionFailed(reason) {
                                    if (reason === ConnectionFailReason.NoSecrets) {
                                        root.passwordTarget = netCol.modelData
                                        netCol.errorText = ""
                                    } else {
                                        netCol.errorText = "Connection failed"
                                    }
                                }
                            }

                            Rectangle {
                                width: parent.width
                                height: 44
                                radius: 8
                                color: netCol.modelData.connected
                                    ? Qt.rgba(Services.Colors.accent.r, Services.Colors.accent.g,
                                              Services.Colors.accent.b, 0.14)
                                    : Services.Colors.surfaceAlt

                                // left: signal bars + name + lock + state
                                Column {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 2

                                    Row {
                                        spacing: 6

                                        // 4-bar signal meter, baseline-aligned
                                        Row {
                                            height: 12
                                            spacing: 2
                                            Repeater {
                                                model: 4
                                                Rectangle {
                                                    width: 3
                                                    height: 4 + index * 2.5
                                                    radius: 1.5
                                                    anchors.bottom: parent.bottom
                                                    color: index < Math.max(1, Math.ceil((netCol.modelData.signalStrength || 0) * 4))
                                                        ? Services.Colors.accent : Services.Colors.low
                                                }
                                            }
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            font.family: Services.Fonts.family
                                            font.pixelSize: 12
                                            font.bold: netCol.modelData.connected
                                            color: netCol.modelData.connected ? Services.Colors.accent
                                                         : Services.Colors.text
                                            text: netCol.modelData.name
                                            elide: Text.ElideRight
                                            width: Math.min(implicitWidth, 150)
                                        }

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: netCol.modelData.security !== WifiSecurityType.Open
                                                  && netCol.modelData.security !== WifiSecurityType.Owe
                                            font.family: Services.Fonts.family
                                            font.pixelSize: 10
                                            color: Services.Colors.textMuted
                                            text: "\uf023"   // nf-fa-lock
                                        }
                                    }

                                    Text {
                                        font.family: Services.Fonts.family
                                        font.pixelSize: 10
                                        color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g,
                                                       Services.Colors.text.b, 0.5)
                                        text: netCol.modelData.connected ? "Connected"
                                            : netCol.modelData.stateChanging ? "Connecting…"
                                            : netCol.modelData.known ? "Saved" : "Not saved"
                                    }
                                }

                                // right: actions
                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 10

                                    Text {
                                        visible: !netCol.modelData.connected && !netCol.modelData.stateChanging
                                        font.family: Services.Fonts.family
                                        font.pixelSize: 11
                                        font.bold: true
                                        color: Services.Colors.accent
                                        text: "Connect"
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                netCol.errorText = ""
                                                Services.Network.connectToNetwork(netCol.modelData)
                                            }
                                        }
                                    }
                                    Text {
                                        visible: netCol.modelData.connected
                                        font.family: Services.Fonts.family
                                        font.pixelSize: 11
                                        color: Services.Colors.text
                                        text: "Disconnect"
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: netCol.modelData.disconnect()
                                        }
                                    }
                                    Text {
                                        visible: netCol.modelData.known
                                        font.family: Services.Fonts.family
                                        font.pixelSize: 11
                                        color: Services.Colors.critical
                                        text: "Forget"
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                if (root.passwordTarget === netCol.modelData)
                                                    root.passwordTarget = null
                                                netCol.modelData.forget()
                                            }
                                        }
                                    }
                                }
                            }

                            // inline password prompt — appears when
                            // connect() fails with NoSecrets
                            Row {
                                visible: root.passwordTarget === netCol.modelData
                                width: parent.width
                                spacing: 6

                                Rectangle {
                                    width: parent.width - 44
                                    height: 28
                                    radius: 6
                                    color: Services.Colors.background
                                    border.color: pwField.activeFocus ? Services.Colors.accent
                                                : Services.Colors.low
                                    border.width: 1

                                    TextInput {
                                        id: pwField
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        verticalAlignment: TextInput.AlignVCenter
                                        clip: true
                                        echoMode: TextInput.Password
                                        passwordCharacter: "•"
                                        font.family: Services.Fonts.family
                                        font.pixelSize: 11
                                        color: Services.Colors.text
                                        // kimi default (NetworkRow.qml:159 focus:
                                        // root.awaitingPassword)
                                        focus: root.passwordTarget === netCol.modelData
                                        onAccepted: submitPw()
                                    }

                                    // focus the field the moment it exists —
                                    // otherwise keys land nowhere (see Bar.qml
                                    // clipboard note about unfocusable fields).
                                    // onVisibleChanged alone misses rows born
                                    // already-visible after a Repeater rebuild.
                                    onVisibleChanged: if (visible)
                                        Qt.callLater(() => pwField.forceActiveFocus())
                                    Component.onCompleted: if (visible)
                                        Qt.callLater(() => pwField.forceActiveFocus())
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    font.family: Services.Fonts.family
                                    font.pixelSize: 11
                                    font.bold: true
                                    color: Services.Colors.accent
                                    text: "Go"
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: netCol.submitPw()
                                    }
                                }
                            }

                            function submitPw() {
                                root.passwordTarget = null
                                Services.Network.connectToNetworkWithPsk(netCol.modelData, pwField.text)
                            }

                            Text {
                                visible: netCol.errorText !== ""
                                font.family: Services.Fonts.family
                                font.pixelSize: 10
                                color: Services.Colors.critical
                                text: netCol.errorText
                            }
                        }
                    }

                    Text {
                        visible: root.netRows.length === 0
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        font.family: Services.Fonts.family
                        font.pixelSize: 11
                        color: Services.Colors.textMuted
                        text: Services.Network.wifiDevice
                            ? "Scanning… networks appear as NetworkManager reports them"
                            : "Wi-Fi is off — flip the switch above"
                    }
                }
            }
        }
    }
}
