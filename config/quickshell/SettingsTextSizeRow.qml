import QtQuick
import Quickshell
import Quickshell.Io
import "./services" as Services

// Text-size row — the renderer's `textsize` row type: the slider's
// track/handle/readout language, but the value lives OUTSIDE hyprland.
// Reads the live px from the trailing number of gsettings font-name
// (set-text-size.sh's state file is the fallback for a session where
// dconf is unavailable, else the 11 default), commits on RELEASE to
// scripts/set-text-size.sh — which patches the gsettings/GTK/kitty/foot
// sizes together and keeps every family as picked — then re-reads what
// actually landed (the dropdown's fontProc rule). Apply/Revert wired:
// commit registers extChanged("textSize", …) so the footer's Apply
// re-runs the script (idempotent keep) and Revert re-runs it with the
// baseline — extRestored then re-reads what actually landed. The sample
// line under the slider IS the preview: it tracks the dragged value
// instantly while real writes stay release-only.
// NOTE: quickshell's own UI text is hardcoded px and does
// not follow this — the row description says GTK apps and terminals.
Item {
    id: root

    // the renderer passes the catalog entry to every row component —
    // this row is fixed-config (no fields read), it just accepts it
    property var e: null

    readonly property real min: 9
    readonly property real max: 20
    readonly property real step: 1
    readonly property string suffix: "px"

    property real live: 11
    property real pending: 11
    property bool dragging: false
    readonly property real shown: dragging ? pending : live
    readonly property real extraHeight: previewSample.height + 8   // sample line grows the row

    width: 214
    height: 30 + extraHeight

    function clamp(v) { return Math.max(min, Math.min(max, v)) }
    function snap(v) { return clamp(Math.round(v / step) * step) }

    function commit(next) {
        const wanted = snap(next)
        pending = wanted
        dragging = false
        // Apply/Revert baseline: the value BEFORE this write (the slider's
        // hyprChanged rule), then the live script
        Services.SettingsApp.extChanged("textSize", root.live, wanted)
        live = wanted
        wr.command = [Quickshell.shellDir + "/scripts/set-text-size.sh", String(wanted)]
        wr.running = true
    }

    Component.onCompleted: rd.running = true

    // footer Revert/Apply re-ran the script itself — re-read what landed
    Connections {
        target: Services.SettingsApp
        function onExtRestored() { if (!rd.running) rd.running = true }
    }

    // gsettings first (SettingsDropdownRow's order), state file only for
    // a session where dconf is unavailable: "… Font Mono 11" or plain 11
    Process {
        id: rd
        command: ["bash", "-c",
            'gsettings get org.gnome.desktop.interface font-name 2>/dev/null'
            + ' || cat "$HOME/.local/state/quickshell/text-size" 2>/dev/null'
            + ' || true']
        stdout: StdioCollector {
            onStreamFinished: {
                const m = String(text).trim().match(/(\d+)\s*'?$/)
                if (m) root.live = root.clamp(parseFloat(m[1]))
            }
        }
    }
    Process {
        id: wr
        onExited: rd.running = true
    }

    // track / fill / handle / readout — SettingsSliderRow's visuals verbatim
    Row {
        anchors.top: parent.top
        width: parent.width
        height: 30
        spacing: 10

        Item {
            id: trackBox
            width: parent.width - readout.width - parent.spacing
            height: parent.height

            Rectangle {
                id: track
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 6
                radius: 3
                color: Qt.rgba(Services.Colors.text.r, Services.Colors.text.g, Services.Colors.text.b, 0.15)

                Rectangle {
                    width: track.width * (root.shown - root.min) / Math.max(1, root.max - root.min)
                    height: parent.height
                    radius: 3
                    color: Services.Colors.accent
                    Behavior on width { SpringAnimation { spring: Services.Motion.bounceSpring; damping: Services.Motion.bounceDamping } }
                }

                Rectangle {
                    id: handle
                    x: (track.width - width) * (root.shown - root.min) / Math.max(1, root.max - root.min)
                    anchors.verticalCenter: parent.verticalCenter
                    width: 14
                    height: 14
                    radius: 7
                    color: Services.Colors.accent
                    border.color: Services.Colors.background
                    border.width: 2
                }

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8          // generous grab zone
                    cursorShape: Qt.PointingHandCursor
                    onPressed: mouse => beginDrag(mouse.x)
                    onPositionChanged: mouse => { if (pressed) beginDrag(mouse.x) }
                    onReleased: root.commit(root.pending)

                    function beginDrag(x) {
                        const norm = Math.max(0, Math.min(1, x / track.width))
                        root.dragging = true
                        root.pending = root.snap(root.min + norm * (root.max - root.min))
                    }
                }
            }
        }

        Text {
            font.family: Services.Fonts.family
            id: readout
            anchors.verticalCenter: parent.verticalCenter
            width: 58
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.shown) + (root.suffix !== "" ? " " + root.suffix : "")
            color: Services.Colors.textMuted
            font.pixelSize: 12
            font.bold: true
        }
    }

    // THE PREVIEW — the row's own sample line tracks the dragged value
    // instantly (real writes stay release-only), so moving the slider has
    // an immediate, visible effect right here in the settings window
    Text {
        font.family: Services.Fonts.family
        id: previewSample
        anchors.top: parent.top
        anchors.topMargin: 34
        width: parent.width
        height: Math.max(22, Math.round(root.shown) + 8)
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: "The quick brown fox — Aa 0123"
        font.pixelSize: Math.round(root.shown)
        color: Services.Colors.textMuted
    }
}
