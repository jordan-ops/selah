pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire

// Voice conversation state for the selah-voice push-to-talk loop
// (SUPER+D). The script ~/.local/bin/selah-voice owns the mic through
// ffmpeg and walks the capsule through the whole round trip over IPC —
// there are NO notifications anywhere, the capsule is the single
// feedback surface:
//   qs ipc call voicerec start               — tap 1, ffmpeg records
//   qs ipc call voicerec stop                — tap 2, wav finalizes
//   qs ipc call voicerec state transcribing "" — whisper is chewing
//   qs ipc call voicerec state thinking "<heard>" — agent turn runs
//   qs ipc call voicerec state speaking ""   — Piper reads the reply
//   qs ipc call voicerec state miss ""       — nothing usable (a beat)
//   qs ipc call voicerec dismiss             — capsule springs away
// `note` carries the transcript into the capsule (the "what I heard"
// line while thinking). The peak is a native PipeWire tap on the
// default source (PwNodePeakMonitor) — no second capture process, no
// parsing: the same stream ffmpeg records, metered by the compositor's
// own audio graph. The monitor is only enabled while recording, so
// idle cost is zero.
Singleton {
    id: root

    property bool recording: false
    property double startedAt: 0
    // bumps on every start — the capsule re-runs its entrance spring
    property int serial: 0
    // "idle" = capsule gone; every other value renders in the capsule
    property string phase: "idle"
    // short detail shown in the capsule (the transcript while thinking)
    property string note: ""

    PwNodePeakMonitor {
        id: peakMon
        node: Pipewire.defaultAudioSource
        enabled: root.recording
    }
    readonly property real peak: root.recording ? Math.max(0, peakMon.peak) : 0

    function start(): void {
        if (root.recording) return
        root.recording = true
        root.startedAt = Date.now()
        root.serial++
        root.phase = "recording"
        root.note = ""
    }
    function stop(): void {
        if (!root.recording) return
        root.recording = false
    }
    // the script walks the capsule through the phases; "idle" ends it
    // (same as dismiss — the capsule springs away either way)
    function state(p: string, detail: string): void {
        root.phase = p
        root.note = detail
    }
    function dismiss(): void {
        root.phase = "idle"
        root.note = ""
    }

    IpcHandler {
        target: "voicerec"
        function start(): void { root.start() }
        function stop(): void { root.stop() }
        function state(p: string, detail: string): void { root.state(p, detail) }
        function dismiss(): void { root.dismiss() }
        function toggle(): void { root.recording ? root.stop() : root.start() }
    }

    // A quickshell reload mid-round-trip must not strand the capsule or
    // lose a half-minute take's UI: the script leaves pid files behind
    // (recording take / detached reply worker), so adopt whatever is
    // live on load (elapsed restarts, the transcript line is gone —
    // best effort).
    Component.onCompleted: adopt.running = true
    Process {
        id: adopt
        command: ["sh", "-c",
            "if test -f /tmp/selah-voice-rec.pid && kill -0 \"$(cat /tmp/selah-voice-rec.pid)\" 2>/dev/null; then echo recording; " +
            "elif test -f /tmp/selah-voice-worker.pid && kill -0 \"$(cat /tmp/selah-voice-worker.pid)\" 2>/dev/null; then echo thinking; fi"]
        stdout: StdioCollector {
            onStreamFinished: {
                const t = text.trim()
                if (t === "recording") {
                    root.recording = true
                    root.startedAt = Date.now()
                    root.phase = "recording"
                } else if (t === "thinking") {
                    root.phase = "thinking"
                }
            }
        }
    }
}
