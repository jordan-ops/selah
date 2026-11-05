import QtQuick
import Quickshell
import Quickshell.Io
import "../services" as Services

// Text-size row — the renderer's `textsize` row type: the control is
// SettingsFrostSlider (the widget studio's M3Slider behind a
// display-unit facade), so the settings window and the widget editor
// share one slider language, and the value lives OUTSIDE hyprland.
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
    // ready = the async gsettings read has landed — until then the
    // slider stays invisible (layout reserved) instead of flashing 11
    property bool ready: false
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
                // read settled either way — reveal the control (an empty
                // read keeps the 11 default rather than an invisible row)
                root.ready = true
            }
        }
    }
    Process {
        id: wr
        onExited: rd.running = true
    }

    // track / handle / readout — SettingsFrostSlider, the same control
    // SettingsSliderRow uses (moved = live drag preview into `pending`
    // and the sample line, committed = release → the write path above)
    Row {
        anchors.top: parent.top
        width: parent.width
        height: 30
        spacing: 10

        SettingsFrostSlider {
            id: frost
            width: parent.width - readout.width - parent.spacing
            height: parent.height
            value: root.shown
            from: root.min
            to: root.max
            step: root.step
            suffix: root.suffix
            disabled: !root.enabled || !root.ready
            onMoved: v => {
                root.dragging = true
                root.pending = root.snap(v)
            }
            onCommitted: v => root.commit(v)
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

    // Before the gsettings read lands, the control zone stays invisible
    // (layout is reserved, so nothing shifts when it appears)
    opacity: root.ready ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 120 } }

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
