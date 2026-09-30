pragma Singleton
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick

Singleton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool muted: sink?.audio.muted ?? false
    readonly property real volume: sink?.audio.volume ?? 0   // 0.0–1.0

    function toggleMute() {
        if (sink?.audio) sink.audio.muted = !sink.audio.muted
    }

    // control-center slider entry point (0..1, same range the slider shows)
    function setVolume(v) {
        if (sink?.audio) sink.audio.volume = Math.min(1, Math.max(0, v))
    }

    // Output devices — real hardware/virtual sinks (speakers, headphones,
    // HDMI...), filtered out of Pipewire's full node list which also
    // contains every per-app playback stream (Firefox, Spotify, etc).
    // Waybar analogy: this is like grepping `pactl list sinks short` down
    // to just the sink lines, ignoring `pactl list sink-inputs`.
    readonly property var sinks: Pipewire.nodes.values.filter(function(n) {
        return n.isSink && n.audio && !n.isStream
    })

    function setSink(node) {
        // Hint pipewire to switch the default output. defaultAudioSink
        // (above) updates on its own once pipewire actually applies it.
        Pipewire.preferredDefaultAudioSink = node
    }

    function isCurrentSink(node) {
        return sink !== null && node.id === sink.id
    }

    // keeps pipewire from garbage-collecting the node references —
    // sink plus every node we're displaying in the device picker
    PwObjectTracker {
        objects: [sink].concat(root.sinks)
    }
}