pragma Singleton
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import QtQuick

// Waybar analogy: like a "custom/recording" module, except the actual
// wf-recorder process, its audio routing, and the elapsed-time counter all
// live here so the bar icon and the popup both read the same state.
//
// Audio routing:
//   none        → no -a flag
//   mic only    → -a (wf-recorder's own default source)
//   system only → pactl null sink + loopback from @DEFAULT_SINK@.monitor,
//                 record from the null sink's monitor
//   both        → same null sink + an extra loopback from @DEFAULT_SOURCE@
//                 (mic) into it, so both end up mixed on one monitor
// The null sink is torn down after every recording, saved or discarded.
//
// Compression (the card's Compress toggle, on by default):
//   a stopped recording is re-encoded by ffmpeg (h264 crf 23) in place of
//   the near-lossless original — "Processing image" fires when it starts,
//   "Video saved" when the compressed file has replaced the raw one. The
//   raw file survives untouched whenever the encode fails.
Singleton {
    id: root

    property string captureTarget: "screen"   // "screen" | "window" | "region"
    property bool audioMic: false
    property bool audioSystem: false

    readonly property string captureIcon: captureTarget === "window" ? "󱂬"
        : captureTarget === "region" ? "󰩭" : "󰍹"
    readonly property string captureLabel: captureTarget === "window" ? "Window"
        : captureTarget === "region" ? "Region" : "Screen"
    readonly property string audioLabel: {
        if (audioMic && audioSystem) return "Mic + Sys"
        if (audioMic) return "Mic"
        if (audioSystem) return "Sys"
        return "None"
    }

    function setCaptureTarget(t) {
        if (t === "screen" || t === "window" || t === "region") {
            root.captureTarget = t
            if (!root.recording && !root.starting)
                root.lastError = ""
        }
    }
    function toggleMic() { root.audioMic = !root.audioMic }
    function toggleSystem() { root.audioSystem = !root.audioSystem }

    // Compress the file AFTER the recording stops (see the post-processing
    // block below). The value lives in settings.json so it survives a
    // shell reload, and the card's toggle writes it back through set().
    readonly property bool compress: Settings.recordingCompress
    function toggleCompress() {
        Settings.set("recording.compress", !root.compress)
    }

    property bool open: false
    // Multi-monitor: overlay state is shared, but every screen has its own
    // bar. The bar that opens this overlay records itself here and only it
    // reacts — without an owner, every bar showed the panel AND armed its
    // own HyprlandFocusGrab; the duplicate grabs fought over keyboard focus
    // and cleared each other the instant they activated, so no panel ever
    // appeared once a second display was connected.
    property string ownerScreen: ""
    onOpenChanged: {
        if (open) {
            const fm = Hyprland.focusedMonitor
            ownerScreen = fm ? fm.name
                : (Quickshell.screens.length > 0 ? Quickshell.screens[0].name : "")
        }
    }

    // The pill's modes are exclusive — opening the recording card dismisses
    // the siblings so the mode chain can't show something else under the
    // panel the user just asked for. Updates is a direct call here rather
    // than a Connections target: two singletons watching each other's `open`
    // at instantiation time is a circular-creation hazard.
    function openPanel() {
        Launcher.closeLauncher()
        Themes.closePicker()
        Wallpapers.closePicker()
        ControlCenter.close()
        ClockCard.close()
        Clipboard.close()
        PowerMenu.open = false
        Media.close()
        Updates.close()
        root.open = true
    }
    function toggle() { root.open ? root.close() : root.openPanel() }
    function close() { root.open = false }

    // and the reverse: any sibling panel taking the pill closes the card,
    // so `open` never sits true under another mode
    function dismiss() { if (root.open) root.open = false }
    Connections { target: Launcher;      function onOpenChanged() { if (Launcher.open) root.dismiss() } }
    Connections { target: Themes;        function onOpenChanged() { if (Themes.open) root.dismiss() } }
    Connections { target: Wallpapers;    function onOpenChanged() { if (Wallpapers.open) root.dismiss() } }
    Connections { target: ControlCenter; function onOpenChanged() { if (ControlCenter.open) root.dismiss() } }
    Connections { target: ClockCard;     function onOpenChanged() { if (ClockCard.open) root.dismiss() } }
    Connections { target: Clipboard;     function onOpenChanged() { if (Clipboard.open) root.dismiss() } }
    Connections { target: PowerMenu;     function onOpenChanged() { if (PowerMenu.open) root.dismiss() } }
    Connections { target: Media;         function onOpenChanged() { if (Media.open) root.dismiss() } }

    // ── Recording state ────────────────────────────────────────────────
    property bool recording: false
    property bool starting: false
    property int elapsed: 0
    property string lastError: ""
    property string lastFile: ""
    property string _currentFile: ""
    property bool _discarding: false
    property bool _stopRequested: false
    property bool _waitingForRecorderStart: false

    // ── Post-processing state ─────────────────────────────────────────
    // `processing` drives the card's status line while ffmpeg runs. Jobs
    // queue so a second recording stopped before the first re-encode
    // finished is compressed too, never silently skipped — Process can
    // only own one ffmpeg at a time.
    property bool processing: false
    property var _compressQueue: []
    property string _compressSource: ""
    property string _compressTemp: ""

    // Output is deliberately created on demand. wf-recorder does not create
    // parent directories, and the configured video directory may not exist yet.
    readonly property string outputDirectory: Quickshell.env("HOME") + "/Videos"

    property bool _usingNullSink: false
    property string _sinkName: ""
    property string _nullSinkModuleId: ""
    property var _loopbackModuleIds: []
    property string _pendingGeometry: ""

    readonly property bool busy: starting
        || regionSelectProc.running || windowGeometryProc.running
        || prepareProc.running || nullSinkSetup.running
        || loopbackSetup.running || micLoopbackSetup.running
        || recorderProc.running

    readonly property string elapsedDisplay: {
        const m = Math.floor(root.elapsed / 60)
        const s = root.elapsed % 60
        return (m < 10 ? "0" : "") + m + ":" + (s < 10 ? "0" : "") + s
    }

    Timer {
        interval: 1000
        running: root.recording
        repeat: true
        onTriggered: root.elapsed++
    }

    function _setError(message) {
        root.lastError = String(message)
        root.starting = false
        console.warn("ScreenRecording: " + root.lastError)
    }

    function _abortStart(message) {
        root._pendingGeometry = ""
        root._stopRequested = false
        root._teardownAudio()
        root._setError(message)
    }

    // ── Start flow ──────────────────────────────────────────────────────
    function startRecording() {
        if (root.recording || root.starting) return
        root.lastError = ""
        root._discarding = false
        root._stopRequested = false
        root.starting = true

        if (root.captureTarget === "region") {
            regionSelectProc.running = true
        } else if (root.captureTarget === "window") {
            windowGeometryProc.running = true
        } else {
            root._beginRecording("")
        }
    }

    // slurp lets you drag a box; empty output means Escape was pressed.
    Process {
        id: regionSelectProc
        command: ["slurp"]
        property string _geometry: ""
        property string _error: ""

        onRunningChanged: {
            if (running) {
                _geometry = ""
                _error = ""
            }
        }
        onExited: exitCode => {
            const geometry = _geometry.trim()
            if (exitCode !== 0) {
                root._abortStart(_error || "Region selection failed")
                return
            }
            if (geometry === "") {
                root.starting = false       // user cancelled with Escape
                return
            }
            root._beginRecording(geometry)
        }
        stdout: SplitParser {
            onRead: line => regionSelectProc._geometry = line.trim()
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    regionSelectProc._error = line.trim()
            }
        }
    }

    // hyprctl's activewindow gives "at": [x,y] and "size": [w,h] — feeds
    // straight into wf-recorder's -g "x,y wxh" geometry format.
    Process {
        id: windowGeometryProc
        command: ["hyprctl", "activewindow", "-j"]
        property string _json: ""
        property string _error: ""

        onRunningChanged: {
            if (running) {
                _json = ""
                _error = ""
            }
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root._abortStart(_error || "Could not read the active window")
                return
            }
            try {
                const win = JSON.parse(_json)
                if (!win || !win.at || !win.size)
                    throw new Error("missing geometry")
                const x = Number(win.at[0])
                const y = Number(win.at[1])
                const w = Number(win.size[0])
                const h = Number(win.size[1])
                if (!isFinite(x) || !isFinite(y) || !isFinite(w) || !isFinite(h)
                        || w <= 0 || h <= 0)
                    throw new Error("invalid geometry")
                root._beginRecording(x + "," + y + " " + w + "x" + h)
            } catch (e) {
                root._abortStart("No active window is available to record")
            }
        }
        stdout: SplitParser {
            onRead: line => windowGeometryProc._json += line + "\n"
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    windowGeometryProc._error = line.trim()
            }
        }
    }

    function _beginRecording(geometry) {
        root._pendingGeometry = geometry
        prepareProc.running = true
    }

    // wf-recorder cannot open a file below a missing directory. Create the
    // directory first, then continue with audio setup or the recorder itself.
    Process {
        id: prepareProc
        command: ["mkdir", "-p", root.outputDirectory]
        property string _error: ""

        onRunningChanged: {
            if (running)
                _error = ""
        }
        onExited: exitCode => {
            if (!root.starting) return
            if (exitCode !== 0) {
                root._abortStart("Could not create " + root.outputDirectory
                    + (_error ? ": " + _error : ""))
                return
            }
            root._afterPrepare()
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    prepareProc._error = line.trim()
            }
        }
    }

    function _afterPrepare() {
        if (root.audioSystem) {
            // A unique sink prevents a crashed shell from leaving a stale
            // fixed-name sink that makes the next recording fail.
            root._usingNullSink = true
            root._sinkName = "quickshell_rec_" + Date.now()
            root._nullSinkModuleId = ""
            root._loopbackModuleIds = []
            nullSinkSetup._id = ""
            nullSinkSetup._error = ""
            nullSinkSetup.command = [
                "pactl", "load-module", "module-null-sink",
                "sink_name=" + root._sinkName,
                "sink_properties=device.description=" + root._sinkName
            ]
            nullSinkSetup.running = true
        } else {
            root._launchRecorder(root._pendingGeometry, root.audioMic ? "mic" : "none")
        }
    }

    Process {
        id: nullSinkSetup
        property string _id: ""
        property string _error: ""

        onExited: exitCode => {
            if (!root.starting) return
            if (exitCode !== 0 || _id === "") {
                root._abortStart("Could not create the system-audio sink"
                    + (_error ? ": " + _error : ""))
                return
            }
            root._nullSinkModuleId = _id
            loopbackSetup._id = ""
            loopbackSetup._error = ""
            loopbackSetup.running = true
        }
        stdout: SplitParser {
            onRead: line => {
                const id = line.trim()
                if (/^[0-9]+$/.test(id))
                    nullSinkSetup._id = id
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    nullSinkSetup._error = line.trim()
            }
        }
    }

    Process {
        id: loopbackSetup
        command: ["pactl", "load-module", "module-loopback",
            "source=@DEFAULT_SINK@.monitor", "sink=" + root._sinkName]
        property string _id: ""
        property string _error: ""

        onExited: exitCode => {
            if (!root.starting) return
            if (exitCode !== 0 || _id === "") {
                root._abortStart("Could not capture system audio"
                    + (_error ? ": " + _error : ""))
                return
            }
            root._loopbackModuleIds = root._loopbackModuleIds.concat([_id])
            if (root.audioMic) {
                micLoopbackSetup._id = ""
                micLoopbackSetup._error = ""
                micLoopbackSetup.running = true
            } else {
                root._launchRecorder(root._pendingGeometry, "nullsink")
            }
        }
        stdout: SplitParser {
            onRead: line => {
                const id = line.trim()
                if (/^[0-9]+$/.test(id))
                    loopbackSetup._id = id
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    loopbackSetup._error = line.trim()
            }
        }
    }

    Process {
        id: micLoopbackSetup
        command: ["pactl", "load-module", "module-loopback",
            "source=@DEFAULT_SOURCE@", "sink=" + root._sinkName]
        property string _id: ""
        property string _error: ""

        onExited: exitCode => {
            if (!root.starting) return
            if (exitCode !== 0 || _id === "") {
                root._abortStart("Could not capture microphone audio"
                    + (_error ? ": " + _error : ""))
                return
            }
            root._loopbackModuleIds = root._loopbackModuleIds.concat([_id])
            root._launchRecorder(root._pendingGeometry, "nullsink")
        }
        stdout: SplitParser {
            onRead: line => {
                const id = line.trim()
                if (/^[0-9]+$/.test(id))
                    micLoopbackSetup._id = id
            }
        }
        stderr: SplitParser {
            onRead: line => {
                if (line.trim() !== "")
                    micLoopbackSetup._error = line.trim()
            }
        }
    }

    function _launchRecorder(geometry, audioMode) {
        const now = new Date()
        const pad = n => (n < 10 ? "0" : "") + n
        const millis = (now.getMilliseconds() + 1000) % 1000
        const millisText = (millis < 10 ? "00" : millis < 100 ? "0" : "") + millis
        const stamp = now.getFullYear() + pad(now.getMonth() + 1) + pad(now.getDate())
            + "-" + pad(now.getHours()) + pad(now.getMinutes()) + pad(now.getSeconds())
            + "-" + millisText
        const filename = root.outputDirectory + "/recording-" + stamp + ".mp4"
        root._currentFile = filename
        root.lastFile = ""
        root._stopRequested = false

        // Process.command is an argv list; do not build a shell command. This
        // keeps paths/geometry safe and lets Process.signal(2) reach the actual
        // wf-recorder process when the user presses Stop.
        const command = ["wf-recorder", "-f", filename]
        if (geometry !== "")
            command.push("-g", geometry)
        if (audioMode === "mic")
            command.push("-a")
        if (audioMode === "nullsink")
            command.push("-a=" + root._sinkName + ".monitor")

        recorderProc._lastOutput = ""
        recorderProc.command = command
        root._waitingForRecorderStart = true
        recorderStartTimer.restart()
        recorderProc.running = true
    }

    // Process reports normal exits, but a missing executable can fail before
    // it emits an exit signal on some Qt versions. Do not leave the UI stuck
    // in "Starting…" in that case.
    Timer {
        id: recorderStartTimer
        interval: 5000
        repeat: false
        onTriggered: {
            if (root._waitingForRecorderStart && !root.recording) {
                if (recorderProc.running)
                    recorderProc.signal(9)
                root._waitingForRecorderStart = false
                root._finishRecorder(-1)
                root.lastError = "wf-recorder did not start"
            }
        }
    }

    Process {
        id: recorderProc
        property string _lastOutput: ""

        onStarted: {
            root._waitingForRecorderStart = false
            recorderStartTimer.stop()
            root.recording = true
            root.starting = false
            root.lastError = ""
            root.elapsed = 0
        }
        onExited: exitCode => {
            if (root._currentFile === "" && !root.recording && !root.starting)
                return
            root._finishRecorder(exitCode)
        }
        stderr: SplitParser {
            onRead: line => {
                const text = line.trim()
                if (text !== "")
                    recorderProc._lastOutput = text
            }
        }
    }

    function _finishRecorder(exitCode) {
        const file = root._currentFile
        const discard = root._discarding
        const intentional = root._stopRequested

        root.recording = false
        root.starting = false
        root._waitingForRecorderStart = false
        recorderStartTimer.stop()
        root._stopRequested = false
        root._teardownAudio()

        if (discard && file !== "") {
            deleteProc.command = ["rm", "-f", file]
            deleteProc.running = true
        } else if (intentional || exitCode === 0) {
            root.lastFile = file
            if (root.compress && file !== "")
                root._startCompression(file)
            else if (file !== "")
                Quickshell.execDetached(["notify-send", "Video saved", file])
        } else {
            const detail = recorderProc._lastOutput
            root.lastError = "wf-recorder failed (exit " + exitCode + ")"
                + (detail ? ": " + detail : "")
            console.warn(root.lastError)
        }

        root._discarding = false
        root._currentFile = ""
        root._pendingGeometry = ""
    }

    Process { id: deleteProc }

    // ── Post-processing: optional compression ─────────────────────────
    // wf-recorder's default is near-lossless x264, which is why the files
    // came out huge. With Compress on, the stop path above hands the fresh
    // file here: ffmpeg re-encodes to a temp file beside it, and only a
    // clean encode followed by a rename replaces the original — any
    // failure deletes the temp and leaves the uncompressed recording as
    // the saved file.
    function _startCompression(source) {
        root._compressQueue = root._compressQueue.concat([{
            source: source,
            temp: source + ".compressing.mp4"
        }])
        root._pumpCompression()
    }

    function _pumpCompression() {
        if (root.processing || root._compressQueue.length === 0) return
        const job = root._compressQueue[0]
        root._compressQueue = root._compressQueue.slice(1)
        root._compressSource = job.source
        root._compressTemp = job.temp
        root.processing = true

        // Exactly the words asked for; the shell's own NotificationServer
        // puts it in the pill, same transport as Battery/Updates' calls.
        Quickshell.execDetached(["notify-send", "Processing image"])

        compressProc._lastOutput = ""
        // -nostdin so ffmpeg can never stall on input Process won't send;
        // crf 23 keeps text crisp while shedding most of the bulk.
        compressProc.command = [
            "ffmpeg", "-nostdin", "-y",
            "-i", job.source,
            "-c:v", "libx264", "-crf", "23", "-preset", "veryfast",
            "-pix_fmt", "yuv420p",
            "-c:a", "aac", "-b:a", "128k",
            job.temp
        ]
        compressProc.running = true
    }

    function _compressionDone() {
        const source = root._compressSource
        root.processing = false
        root._compressSource = ""
        root._compressTemp = ""
        root.lastFile = source
        Quickshell.execDetached(["notify-send", "Video saved", source])
        root._pumpCompression()
    }

    function _compressionFailed(detail) {
        const source = root._compressSource
        const temp = root._compressTemp
        root.processing = false
        root._compressSource = ""
        root._compressTemp = ""
        if (temp !== "") {
            cleanupProc.command = ["rm", "-f", temp]
            cleanupProc.running = true
        }
        // the original was never touched — it stays the saved recording
        root.lastFile = source
        root.lastError = "Compression failed: " + detail
        console.warn(root.lastError)
        Quickshell.execDetached(["notify-send", "-u", "critical",
            "Compression failed", source])
        root._pumpCompression()
    }

    Process {
        id: compressProc
        property string _lastOutput: ""

        onExited: exitCode => {
            if (exitCode === 0) {
                moveProc.command = ["mv", "-f",
                    root._compressTemp, root._compressSource]
                moveProc.running = true
            } else {
                root._compressionFailed("ffmpeg exited " + exitCode
                    + (compressProc._lastOutput !== ""
                        ? ": " + compressProc._lastOutput : ""))
            }
        }
        stderr: SplitParser {
            onRead: line => {
                const text = line.trim()
                if (text === "") return
                // ffmpeg interleaves its \r progress dumps into the SAME
                // chunk as the real message, so keep only what follows the
                // last \r and skip a chunk that is pure progress — then
                // cap it so one message can't blow up the status line.
                const tail = text.split("\r").pop().trim()
                if (tail === "" || tail.startsWith("frame=")) return
                compressProc._lastOutput = tail.slice(-300)
            }
        }
    }

    // The rename is what actually swaps the compressed file in — its own
    // step so a failed encode can never half-overwrite the recording.
    Process {
        id: moveProc
        onExited: exitCode => {
            if (exitCode === 0)
                root._compressionDone()
            else
                root._compressionFailed("could not move the compressed file into place")
        }
    }

    Process { id: cleanupProc }

    // wf-recorder needs SIGINT (not a hard kill) to finalize the container
    // and write a playable file. Quickshell's Process.signal targets only this
    // recorder instead of pkill -f, which could hit an unrelated recording.
    function stopRecording() {
        if (!root.recording) return
        root._stopRequested = true
        recorderProc.signal(2)
    }

    function discardRecording() {
        if (root.recording) {
            root._discarding = true
            root.stopRecording()
        } else if (root.starting) {
            root._abortStart("Recording cancelled")
        }
    }

    function _teardownAudio() {
        let ids = []
        if (root._loopbackModuleIds && root._loopbackModuleIds.length > 0)
            ids = ids.concat(root._loopbackModuleIds)
        if (root._nullSinkModuleId !== "")
            ids.push(root._nullSinkModuleId)

        root._usingNullSink = false
        root._sinkName = ""
        root._nullSinkModuleId = ""
        root._loopbackModuleIds = []

        const validIds = ids.filter(id => /^[0-9]+$/.test(String(id)))
        if (validIds.length === 0)
            return
        teardownProc.command = [
            "sh", "-c", validIds.map(id => "pactl unload-module " + id).join(" ; ")
        ]
        teardownProc.running = true
    }
    Process { id: teardownProc }

    // Useful for keybinds, scripts, and diagnosing the recorder without
    // having to click the popup: qs ipc call screenrecord start|stop|status.
    IpcHandler {
        target: "screenrecord"
        function start(): void { root.startRecording() }
        function stop(): void { root.stopRecording() }
        function discard(): void { root.discardRecording() }
        function toggle(): void {
            if (root.recording)
                root.stopRecording()
            else
                root.startRecording()
        }
        function setTarget(target: string): void { root.setCaptureTarget(target) }
        function setAudio(mic: bool, system: bool): void {
            root.audioMic = mic
            root.audioSystem = system
        }
        function setCompress(compress: bool): void {
            Settings.set("recording.compress", compress)
        }
        function toggleCompress(): void { root.toggleCompress() }
        function open(): void { root.openPanel() }
        function close(): void { root.open = false }
        function status(): string {
            return JSON.stringify({
                recording: root.recording,
                starting: root.starting,
                processing: root.processing,
                target: root.captureTarget,
                mic: root.audioMic,
                system: root.audioSystem,
                compress: root.compress,
                file: root.lastFile,
                error: root.lastError
            })
        }
    }
}
