pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Io
import QtQuick

Singleton {
    id: root

    // ----- in-bar card state (same recipe as ClockCard) -----
    // Media lives INSIDE the bar now: the little equaliser in the pill's
    // rest row (modules/MediaVisualiser.qml) is the click target and the
    // pill itself morphs into the card (pill.mode -> "media"). The old
    // activity chip + detached mediaPopup PopupWindow are gone.
    // Multi-monitor: the bar that opens the card records its screen here,
    // and only that bar morphs (ownsOverlay in Bar.qml).
    property bool open: false
    property string ownerScreen: ""
    onOpenChanged: {
        if (open) {
            const fm = Hyprland.focusedMonitor
            ownerScreen = fm ? fm.name
                : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
        }
    }

    function toggle() { open = hasPlayer ? !open : false }
    function close() { open = false }

    // prefer an actively-playing player, but fall back to any existing
    // player (paused counts) — a closed app is the only thing that should
    // make hasPlayer false
    readonly property var activePlayer: {
        const playing = Mpris.players.values.find(p => p.isPlaying)
        if (playing) return playing
        return Mpris.players.values.length > 0 ? Mpris.players.values[0] : null
    }

    readonly property bool hasPlayer: activePlayer !== null
    // the card is player-backed: fold it the moment the last player exits
    // (the visualiser collapses with it — both key off hasPlayer)
    onHasPlayerChanged: if (!hasPlayer) open = false

    readonly property bool playing: hasPlayer && activePlayer.isPlaying

    readonly property string title: hasPlayer ? (activePlayer.trackTitle || "Unknown Title") : ""
    readonly property string artist: hasPlayer ? (activePlayer.trackArtist || "Unknown Artist") : ""
    readonly property string artUrl: hasPlayer ? (activePlayer.trackArtUrl || "") : ""

    // Themed app icon for the card header — desktopEntry first (that's
    // the icon name), then identity, then identity with spaces squeezed
    // to dashes. cliamp advertises NO desktopEntry but ships
    // hicolor/512x512/apps/cliamp.png matching its identity, so it gets
    // its real icon. iconPath(name, true) is a synchronous local lookup
    // that returns "" on a miss, and every consumer binds this DIRECTLY,
    // so the icon is on screen the frame the player registers — no
    // waiting on desktop-entry metadata that stream players often never
    // send (the "icons update slowly with online music" fix).
    readonly property url appIconSource: {
        if (!hasPlayer) return ""
        const de = (activePlayer.desktopEntry || "").trim().toLowerCase()
        const id = (activePlayer.identity || "").trim().toLowerCase()
        const cands = [de, id, id.replace(/\s+/g, "-")]
        for (const c of cands) {
            if (c === "") continue
            const p = Quickshell.iconPath(c, true)
            if (p !== "") return p
        }
        return ""
    }

    // nerd-glyph fallback shown when no themed icon exists — brand
    // sniffing over desktopEntry AND identity (browsers proxying online
    // radio often only send identity)
    readonly property string appIcon: {
        if (!hasPlayer) return ""
        const key = ((activePlayer.desktopEntry || "") + " "
                    + (activePlayer.identity || "")).toLowerCase()
        if (key.includes("spotify")) return "󰓇"
        if (key.includes("firefox")) return "󰈹"
        if (key.includes("chrome"))  return "󰊯"
        return "󰎆"   // generic music-note fallback for anything unrecognized
    }

    // position/length feed the card's progress rail. MPRIS position
    // doesn't push change notifications (the spec excludes it from
    // PropertiesChanged), so while the card is open AND playing the
    // 1s timer below force-emits the player's positionChanged to make
    // bindings re-read — nothing ticks while the card is closed, which
    // is why this Timer is gated instead of living on forever like the
    // old chip's was. Seeking while paused still updates the rail
    // directly (setting position emits notify itself).
    readonly property real position: hasPlayer ? activePlayer.position : 0
    readonly property real length: hasPlayer ? activePlayer.length : 0

    Timer {
        running: root.open && root.playing
        repeat: true
        interval: 1000
        onTriggered: if (root.hasPlayer) root.activePlayer.positionChanged()
    }

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

    // fraction 0..1 of the track — the card's progress rail calls this
    // on click/drag (MPRIS position is a writable property, seeking is
    // just setting it). canSeek/length guard keeps live streams inert.
    function seek(frac) {
        if (!hasPlayer || !activePlayer.canSeek || length <= 0) return
        activePlayer.position = Math.max(0, Math.min(length, frac * length))
    }

    // same IPC signature the old Bar.qml hook exposed — binds/scripts keep
    // working: qs ipc call media toggle / isExpanded / hasPlayer
    IpcHandler {
        target: "media"
        function toggle(): void { root.toggle() }
        function isExpanded(): bool { return root.open }
        function hasPlayer(): bool { return root.hasPlayer }
    }
}
