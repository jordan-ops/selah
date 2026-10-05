// Ported from Nebula's Widgets/MusicNow.qml (GPL-3.0) — qs.modules imports
// dropped (everything it used is a sibling in widgets/ now).
import QtQuick

QtObject {
    id: root

    property bool preview: false

    readonly property bool hasTrack: root.preview || ServiceMusic.activePlayer !== null
    readonly property string title: root.preview ? "Low Tide Signals"
        : root.hasTrack ? (ServiceMusic.activeTrack?.title ?? "") : "Nothing playing"
    readonly property string artist: root.preview ? "Neon Harbor"
        : root.hasTrack ? (ServiceMusic.activeTrack?.artist ?? "") : "Start something in any player"
    readonly property string album: root.preview ? "Coastal Static"
        : root.hasTrack ? (ServiceMusic.activeTrack?.album ?? "") : ""
    readonly property string albumShown: root.album === "Unknown Album" ? "" : root.album
    readonly property string artUrl: root.preview ? "" : (ServiceMusic.activeTrack?.artUrl ?? "")
    readonly property string source: root.preview ? "Spotify" : (ServiceMusic.activeTrack?.identity ?? "")
    readonly property real length: root.preview ? 222 : ServiceMusic.trackLength
    readonly property real elapsed: root.preview ? 108 : (ServiceMusic.activePlayer?.position ?? 0)
    readonly property real progress: root.length > 0 ? Math.max(0, Math.min(1, root.elapsed / root.length)) : 0
    readonly property bool playing: root.preview || ServiceMusic.isPlaying
    readonly property bool canSeek: !root.preview && (ServiceMusic.activePlayer?.canSeek ?? false) && root.length > 0
    readonly property string elapsedText: ServiceMusic.formatTime(root.elapsed)
    readonly property string lengthText: root.length > 0 ? ServiceMusic.formatTime(root.length) : "--:--"
    readonly property string remainingText: root.length > 0 ? "−" + ServiceMusic.formatTime(Math.max(0, root.length - root.elapsed)) : ""
    readonly property bool shuffle: root.preview ? false : ServiceMusic.hasShuffle
    readonly property string key: root.title + "|" + root.artist

    function toggle() {
        if (!root.preview)
            ServiceMusic.togglePlaying()
    }

    function next() {
        if (!root.preview)
            ServiceMusic.next()
    }

    function previous() {
        if (!root.preview)
            ServiceMusic.previous()
    }

    function seek(fraction) {
        if (root.canSeek)
            ServiceMusic.activePlayer.position = Math.max(0, Math.min(1, fraction)) * root.length
    }

    function toggleShuffle() {
        if (!root.preview && ServiceMusic.shuffleSupported)
            ServiceMusic.setShuffle(!ServiceMusic.hasShuffle)
    }
}
