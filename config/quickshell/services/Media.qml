pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick

Singleton {
    id: root

    // prefer an actively-playing player, but fall back to any existing
    // player (paused counts) — a closed app is the only thing that should
    // make hasPlayer false
    readonly property var activePlayer: {
        const playing = Mpris.players.values.find(p => p.isPlaying)
        if (playing) return playing
        return Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    }

    readonly property bool hasPlayer: activePlayer !== null
    readonly property bool playing: hasPlayer && activePlayer.isPlaying

    readonly property string title: hasPlayer ? (activePlayer.trackTitle || "Unknown Title") : ""
    readonly property string artist: hasPlayer ? (activePlayer.trackArtist || "Unknown Artist") : ""
    readonly property string artUrl: hasPlayer ? (activePlayer.trackArtUrl || "") : ""

    readonly property string appIcon: {
        if (!hasPlayer) return ""
        const entry = (activePlayer.desktopEntry || "").toLowerCase()
        if (entry.includes("spotify")) return "󰓇"
        if (entry.includes("firefox")) return "󰈹"
        if (entry.includes("chrome"))  return "󰊯"
        return "󰎆 "   // generic music-note fallback for anything unrecognized
    }

    readonly property real position: hasPlayer ? activePlayer.position : 0
    readonly property real length: hasPlayer ? activePlayer.length : 0

    function formatTime(seconds){
        const m = Math.floor(seconds / 60)
        const s = Math.floor(seconds % 60)
        return m + ":" + (s < 10 ? "0" : "") + s
    }

    function previous(){
        if (hasPlayer && activePlayer.canGoPrevious) activePlayer.previous()
    }
    function next(){
        if (hasPlayer && activePlayer.canGoNext) activePlayer.next()
    }
    function togglePlay() {
        if (!hasPlayer) return
        activePlayer.playbackState = (activePlayer.playbackState === MprisPlaybackState.Playing)
        ? MprisPlaybackState.Paused
        : MprisPlaybackState.Playing
    }

    // fraction 0..1 of the track — MPRIS position is a writable property,
    // so seeking is just setting it (guarded by canSeek)
    function seek(frac) {
        if (!hasPlayer || !activePlayer.canSeek || length <= 0) return
        activePlayer.position = Math.max(0, Math.min(length, frac * length))
    }

    // force the player to re-report its position every second while playing
    Timer {
        interval: 1000
        running: root.playing
        repeat: true
        onTriggered: root.activePlayer.positionChanged()
    }
}
