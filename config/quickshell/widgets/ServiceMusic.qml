pragma Singleton
import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import "../services" as Services

// Adapter for the ported Nebula widgets (Nebula shell, GPL-3.0): answers
// the member names the widget files bind on, backed by this shell's MPRIS
// service (services/Media.qml) — the active player IS Media.activePlayer,
// so the bar card and the desktop widgets can never disagree about what's
// playing. Upstream's iTunes/yt-dlp art upgrade and matugen colour CLI are
// dropped (artUrl is the player's own); the 1s position tick is kept,
// because MPRIS never pushes position changes and every widget's progress
// rail binds on positionChanged.
Singleton {
    id: root

    readonly property var activePlayer: Services.Media.activePlayer

    readonly property bool isPlaying: Services.Media.playing

    // same shape upstream built in updateTrack() — a plain binding now
    // that nothing mutates it for an art upgrade
    readonly property var activeTrack: {
        const p = root.activePlayer
        if (!p) return null
        return {
            uniqueId: p.uniqueId ?? 0,
            artUrl: p.trackArtUrl ?? "",
            rawArtUrl: p.trackArtUrl ?? "",
            title: p.trackTitle || "Unknown Title",
            artist: p.trackArtist || "Unknown Artist",
            album: p.trackAlbum || "Unknown Album",
            desktopEntry: p.desktopEntry,
            identity: p.identity
        }
    }

    readonly property real trackLength: {
        const p = root.activePlayer
        if (!p) return 0
        const raw = Number(p.metadata?.["mpris:length"])
        if (isFinite(raw) && raw > 0) return raw / 1000000
        return (p.lengthSupported && p.length > 0) ? p.length : 0
    }

    Timer {
        running: root.isPlaying && root.activePlayer !== null
        interval: 1000
        repeat: true
        onTriggered: if (root.activePlayer) root.activePlayer.positionChanged()
    }

    function formatTime(seconds) {
        if (!seconds || seconds <= 0) return "0:00"
        const mins = Math.floor(seconds / 60)
        const secs = Math.floor(seconds % 60)
        return mins + ":" + (secs < 10 ? "0" : "") + secs
    }

    readonly property bool canTogglePlaying: activePlayer?.canTogglePlaying ?? false
    function togglePlaying() {
        if (canTogglePlaying) activePlayer.togglePlaying()
    }

    readonly property bool canGoPrevious: activePlayer?.canGoPrevious ?? false
    function previous() {
        if (canGoPrevious) activePlayer.previous()
    }

    readonly property bool canGoNext: activePlayer?.canGoNext ?? false
    function next() {
        if (canGoNext) activePlayer.next()
    }

    readonly property bool canChangeVolume:
        activePlayer && activePlayer.volumeSupported && activePlayer.canControl

    readonly property bool loopSupported:
        activePlayer && activePlayer.loopSupported && activePlayer.canControl
    readonly property var loopState: activePlayer?.loopState ?? 0
    function setLoopState(s) {
        if (loopSupported) activePlayer.loopState = s
    }

    readonly property bool shuffleSupported:
        activePlayer && activePlayer.shuffleSupported && activePlayer.canControl
    readonly property bool hasShuffle: activePlayer?.shuffle ?? false
    function setShuffle(s) {
        if (shuffleSupported) activePlayer.shuffle = s
    }

    function pauseAll() {
        for (const p of Mpris.players.values)
            if (p.canPause) p.pause()
    }
}
