import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Material clock card — the `timecard` row type. Live ticking clock +
// long date, an NTP tile (on / synced state from timedatectl) with a
// Resync button, and a timezone tile that expands an in-card searchable
// list of /usr/share/zoneinfo zones; picking one applies through
// pkexec timedatectl (a polkit auth dialog appears; cancelling leaves
// everything unchanged).
Item {
    id: root

    property var e: null

    property string clockTxt: ""
    property string dateTxt: ""
    property string tzVal: ""
    property bool ntpOn: false
    property bool ntpSync: false
    property bool tzOpen: false
    property var zones: []

    readonly property bool busy: false

    readonly property var shownZones: {
        if (!tzOpen) return zones
        const q = searchField.text.trim().toLowerCase()
        if (q === "") return zones
        return zones.filter(z => z.toLowerCase().includes(q))
    }

    readonly property real extraHeight: Math.max(0, col.implicitHeight - 64)
    height: col.implicitHeight

    function readTz() { tzProc.running = true }
    function readNtp() { ntpProc.running = true }

    Component.onCompleted: {
        readTz()
        readNtp()
        tick()
    }

    function tick() {
        const d = new Date()
        clockTxt = Qt.formatTime(d, "HH:mm:ss")
        dateTxt = Qt.formatDate(d, "dddd, d MMMM yyyy")
    }

    Timer { interval: 1000; running: true; repeat: true; onTriggered: root.tick() }

    Process {
        id: tzProc
        command: ["timedatectl", "show", "-p", "Timezone"]
        stdout: StdioCollector {
            onStreamFinished: {
                const i = text.indexOf("=")
                root.tzVal = i >= 0 ? text.slice(i + 1).trim() : text.trim()
            }
        }
    }
    Process {
        id: ntpProc
        command: ["bash", "-c", "timedatectl show -p NTP -p NTPSynchronized --value | tr '\\n' ' '"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split(/\s+/)
                root.ntpOn = p[0] === "yes"
                root.ntpSync = p[1] === "yes"
            }
        }
    }
    Process {
        id: zonesProc
        command: ["bash", "-c",
            "find /usr/share/zoneinfo -mindepth 2 -maxdepth 2 -type f" +
            " | sed 's|/usr/share/zoneinfo/||'" +
            " | grep -v -E '^(posix|right)/' | sort"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.zones = text.split("\n").filter(z => z.trim() !== "")
            }
        }
    }
    Process {
        id: applyProc
        onExited: {
            root.readTz()
            root.readNtp()
        }
    }

    function pickZone(z) {
        tzOpen = false
        applyProc.command = ["pkexec", "timedatectl", "set-timezone", z]
        applyProc.running = true
    }
    function resync() {
        applyProc.command = ["pkexec", "timedatectl", "set-ntp", "true"]
        applyProc.running = true
        applyProcRestart.restart()
    }
    // set-ntp leaves NTP on but sync takes a moment — re-read after a beat
    Timer {
        id: applyProcRestart
        interval: 3000
        onTriggered: root.readNtp()
    }

    function toggleTz() {
        tzOpen = !tzOpen
        if (tzOpen && zones.length === 0) zonesProc.running = true
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
                spacing: 12

                // headline — ticking clock left, date right (anchored —
                // a full-width Row spacer would push the date off-card)
                Item {
                    width: cardCol.width
                    height: 34

                    Text {
                        font.family: Services.Fonts.family
                        id: clockText
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.clockTxt
                        font.pixelSize: 26
                        font.bold: true
                        color: Services.Colors.text
                    }
                    Text {
                        font.family: Services.Fonts.family
                        id: dateText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth,
                                        parent.width - clockText.width - 16)
                        text: root.dateTxt
                        font.pixelSize: 11
                        color: Services.Colors.textMuted
                        elide: Text.ElideRight
                        horizontalAlignment: Text.AlignRight
                    }
                }

                // tiles — NTP status + timezone trigger
                Row {
                    width: cardCol.width
                    spacing: 8

                    Item {
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
                                text: "NETWORK TIME"
                                font.pixelSize: 9
                                font.bold: true
                                font.letterSpacing: 1.2
                                color: Services.Colors.textMuted
                            }
                            Text {
                                font.family: Services.Fonts.family
                                text: !root.ntpOn ? "Off"
                                    : (root.ntpSync ? "On · synced" : "On · syncing…")
                                font.pixelSize: 13
                                font.bold: true
                                color: !root.ntpOn ? Services.Colors.critical
                                     : (root.ntpSync ? Services.Colors.text : Services.Colors.accent)
                                elide: Text.ElideRight
                                width: parent.width - 4
                            }
                        }

                        // resync sits over its tile's right side
                        Rectangle {
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: resyncTxt.implicitWidth + 20
                            height: 24
                            radius: 12
                            color: resyncMouse.containsMouse
                                 ? Services.Colors.accent : Services.Colors.background

                            Text {
                                font.family: Services.Fonts.family
                                id: resyncTxt
                                anchors.centerIn: parent
                                text: "Resync"
                                font.pixelSize: 11
                                font.bold: true
                                color: resyncMouse.containsMouse
                                     ? Services.Colors.background : Services.Colors.accent
                            }
                            MouseArea {
                                id: resyncMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.resync()
                            }
                        }
                    }

                    Item {
                        width: (cardCol.width - 8) / 2
                        height: 46

                        Rectangle {
                            anchors.fill: parent
                            radius: 10
                            color: tzMouse.containsMouse
                                 ? Services.Colors.accent : Services.Colors.surfaceAlt
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
                                text: "TIMEZONE"
                                font.pixelSize: 9
                                font.bold: true
                                font.letterSpacing: 1.2
                                color: tzMouse.containsMouse
                                     ? Services.Colors.background : Services.Colors.textMuted
                            }
                            Text {
                                font.family: Services.Fonts.family
                                text: root.tzVal !== "" ? root.tzVal : "—"
                                font.pixelSize: 13
                                font.bold: true
                                color: tzMouse.containsMouse
                                     ? Services.Colors.background : Services.Colors.text
                                elide: Text.ElideRight
                                width: parent.width - 4
                            }
                        }
                        MouseArea {
                            id: tzMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.toggleTz()
                        }
                    }
                }

                // expandable zone picker
                Column {
                    visible: root.tzOpen
                    width: cardCol.width
                    spacing: 6

                    Rectangle {
                        width: parent.width
                        height: 28
                        radius: 14
                        color: Services.Colors.background
                        border.color: Services.Colors.low
                        border.width: 1

                        TextInput {
                            font.family: Services.Fonts.family
                            id: searchField
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            clip: true
                            color: Services.Colors.text
                            font.pixelSize: 12
                            selectionColor: Services.Colors.accent
                            focus: root.tzOpen

                            Text {
                                font.family: Services.Fonts.family
                                visible: searchField.text === ""
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search zones (Europe/Kampala…)"
                                color: Services.Colors.textMuted
                                font.pixelSize: 12
                            }
                        }
                    }

                    Rectangle {
                        width: parent.width
                        height: Math.min(190, Math.max(28, root.shownZones.length * 24 + 8))
                        radius: 10
                        color: Services.Colors.background
                        border.color: Services.Colors.low
                        border.width: 1
                        clip: true

                        Flickable {
                            anchors.fill: parent
                            anchors.margins: 4
                            contentHeight: root.shownZones.length * 24 + 4
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            Column {
                                width: parent.width
                                spacing: 0

                                Repeater {
                                    model: root.shownZones

                                    delegate: Rectangle {
                                        width: parent.width
                                        height: 24
                                        radius: 6
                                        color: zoneMouse.containsMouse
                                             ? Services.Colors.surface : "transparent"

                                        Text {
                                            font.family: Services.Fonts.family
                                            anchors.left: parent.left
                                            anchors.leftMargin: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: parent.width - 16
                                            text: modelData
                                            font.pixelSize: 11
                                            color: modelData === root.tzVal
                                                 ? Services.Colors.accent : Services.Colors.text
                                            elide: Text.ElideRight
                                        }
                                        MouseArea {
                                            id: zoneMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: root.pickZone(modelData)
                                        }
                                    }
                                }

                                Text {
                                    font.family: Services.Fonts.family
                                    visible: root.shownZones.length === 0
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    height: 24
                                    text: "No match"
                                    font.pixelSize: 11
                                    color: Services.Colors.textMuted
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
