import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import "./services" as Services

// Voice conversation capsule — the visual half of the selah-voice
// push-to-talk loop (SUPER+D → ~/.local/bin/selah-voice). The capsule
// takes the BAR'S seat (the pill's own top edge, a pill-like rest
// width) so the whole round trip reads as the bar itself morphing:
//
//   recording    → accent blob (peak-reactive wobble) + live mic
//                  waveform + elapsed — the original recorder capsule
//   transcribing → calm breathing blob + "Transcribing…"
//   thinking     → the words that were heard + drifting dots while the
//                  agent turn runs (this wait used to be silent — the
//                  long turns now have a face)
//   speaking     → the blob emits sound waves while Piper reads the
//                  reply back (the "Blob Sound waves" Lottie idea,
//                  spent on the ANSWER instead of the mic)
//   miss         → "didn't catch that", cleared by the script
//
// The script drives every transition over IPC (voicerec state …) — this
// file only renders. Click-through and input-free.
Scope {
    id: root

    // NOT decorative: quickshell singletons instantiate lazily — this
    // always-evaluated binding is what guarantees VoiceRec (and its
    // `voicerec` IpcHandler) exists at startup instead of on first use,
    // which is exactly when the push-to-talk script needs to reach it
    readonly property bool live: Services.VoiceRec.phase !== "idle"

    // the window outlives the phase by exactly one exit spring (same
    // trick as EdgeLight: an unloaded Loader has no surface to animate
    // on); a phase change while the exit spring runs re-targets vis up
    property bool alive: false

    Connections {
        target: Services.VoiceRec
        // instantiate the window for ANY visible phase — recording and
        // everything the script walks through afterwards
        function onPhaseChanged() {
            if (Services.VoiceRec.phase !== "idle") root.alive = true
        }
    }
    Component.onCompleted: if (root.live) root.alive = true

    Loader {
        active: root.alive
        visible: active

        sourceComponent: PanelWindow {
            id: win
            screen: Quickshell.screens.find(s => s.name === Services.Compositor.monitor?.name)
                ?? Quickshell.screens[0]
            // layer-shell has no center anchor — full-width transparent
            // strip (EdgeLight's pattern), the capsule centers inside it
            anchors { top: true; left: true; right: true }
            // THE MORPH: the capsule takes the pill's own top edge (0
            // anchored, the float gap when the bar floats) instead of
            // hanging under it — springing in from a narrow scaleX it
            // reads as the bar inflating into the recorder
            margins.top: Services.Settings.barFloating ? Services.Settings.barFloatGap : 0
            // FIXED height: the elapsed text grows a column at 10:00 and
            // a per-minute window resize is exactly the Bar.qml lesson —
            // the text slot is wide enough for "99:59" so nothing moves
            implicitHeight: 54
            color: Services.Colors.background
            exclusionMode: ExclusionMode.Ignore
            mask: Region {}                       // never eats a click
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "selah-voicewave"
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            // entrance/exit driver — 1 while shown, 0 while gone. The
            // window itself is a static transparent surface (PanelWindow
            // exposes neither opacity nor scale — animate the CONTENT):
            // the capsule springs in on both and fades with the spring
            property real vis: 0
            property string phase: Services.VoiceRec.phase
            property string note: Services.VoiceRec.note
            // capsule width follows the phase — only the content resizes,
            // the strip window stays a fixed 54 forever
            readonly property real restW:
                  phase === "recording"    ? 330
                : phase === "thinking"     ? 320
                : phase === "transcribing" ? 252
                : phase === "speaking"     ? 232
                :                            236   // miss

            // start/stop live HERE, not in the enclosing Scope: ids inside
            // sourceComponent aren't visible outside the Loader (a ref from
            // Scope level is a ReferenceError — the exit leg learned this),
            // and a new phase during the exit spring must re-target vis
            // upward instead of letting the unload win the race
            Connections {
                target: Services.VoiceRec
                function onPhaseChanged() {
                    if (Services.VoiceRec.phase === "idle") {
                        closeAnim.restart()
                    } else {
                        closeAnim.stop()
                        inAnim.restart()
                    }
                }
            }

            Component.onCompleted: inAnim.start()
            SequentialAnimation {
                id: inAnim
                SpringAnimation {
                    target: win; property: "vis"; to: 1
                    spring: Services.Motion.bounceSpring
                    damping: Services.Motion.bounceDamping
                }
            }
            // spring away, then unload — the next phase builds a FRESH
            // window, so the entrance spring replays every time
            SequentialAnimation {
                id: closeAnim
                SpringAnimation {
                    target: win; property: "vis"; to: 0
                    spring: Services.Motion.bounceSpring
                    damping: Services.Motion.bounceDamping
                }
                ScriptAction { script: root.alive = false }
            }

            // seconds held — recomputed on the waveform tick (the service
            // only publishes startedAt; per-second display is this window's
            // job so nothing in the service has to tick)
            property int secs: 0
            Timer {
                interval: 33; running: true; repeat: true
                onTriggered: win.secs = Math.floor((Date.now() - Services.VoiceRec.startedAt) / 1000)
            }

            Rectangle {
                id: cap
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                width: win.restW
                Behavior on width {
                    SpringAnimation {
                        spring: Services.Motion.bounceSpring
                        damping: Services.Motion.bounceDamping
                    }
                }
                height: 54
                radius: 27
                color: Services.Colors.surface
                border.color: Services.Colors.low
                border.width: 1
                // the capsule springs and fades while the window stays put;
                // the wide x-scale start is what ties it to the bar's pill
                // (non-uniform scale = a Scale transform; the origin sits
                // mid-capsule so it inflates out of the clock position)
                opacity: win.vis
                transform: Scale {
                    origin.x: cap.width / 2
                    origin.y: cap.height / 2
                    xScale: 0.22 + 0.78 * win.vis
                    yScale: 0.84 + 0.16 * win.vis
                }

                Row {
                    anchors.centerIn: parent
                    spacing: 14

                    // ——— the blob: record dot with a living wobble ———
                    // full life while the mic is hot, a calm breath in
                    // the wait phases, nearly flat on a miss
                    Canvas {
                        id: blob
                        width: 22; height: 22
                        anchors.verticalCenter: parent.verticalCenter
                        property real t: 0
                        property real amp: 0    // live peak swells the wobble
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            const cx = 11, cy = 11, base = 7.2, N = 40
                            const gain = win.phase === "recording" ? 1
                                : win.phase === "miss" ? 0.15 : 0.45
                            ctx.beginPath()
                            for (let i = 0; i <= N; i++) {
                                const a = (i / N) * Math.PI * 2
                                const wob = Math.sin(a * 3 + blob.t) * 0.85
                                            + Math.sin(a * 2 - blob.t * 1.3) * 0.6
                                const r = base + wob * (0.9 + blob.amp * 2.4) * gain
                                const x = cx + Math.cos(a) * r
                                const y = cy + Math.sin(a) * r
                                i === 0 ? ctx.moveTo(x, y) : ctx.lineTo(x, y)
                            }
                            ctx.closePath()
                            ctx.fillStyle = Services.Colors.accent
                            ctx.fill()
                        }
                        Timer {
                            interval: 33; running: true; repeat: true
                            onTriggered: {
                                blob.t += win.phase === "recording" ? 0.2 : 0.09
                                blob.amp = win.phase === "recording"
                                    ? Math.min(1, Services.VoiceRec.peak * 1.6) : 0
                                blob.requestPaint()
                            }
                        }
                    }

                    // ——— recording: mic peak history, scrolling right ———
                    Item {
                        id: waveBox
                        visible: win.phase === "recording"
                        width: barsRow.width
                        height: 34
                        anchors.verticalCenter: parent.verticalCenter

                        // attack/decay history: fast up, slow down — the
                        // classic recorder look. Newest at the END (right).
                        property var hist: {
                            const a = []
                            for (let i = 0; i < 24; i++) a.push(0)
                            return a
                        }
                        Timer {
                            interval: 33; repeat: true; running: true
                            onTriggered: {
                                const p = Math.min(1, Services.VoiceRec.peak * 1.6)
                                const h = waveBox.hist.slice()
                                const smooth = p >= h[h.length - 1] ? p : h[h.length - 1] * 0.86
                                h.push(smooth)
                                h.shift()
                                waveBox.hist = h
                            }
                        }

                        Row {
                            id: barsRow
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4
                            Repeater {
                                model: waveBox.hist.length
                                delegate: Item {
                                    required property int index
                                    width: 3; height: 34
                                    readonly property real v: waveBox.hist[index] ?? 0
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 3
                                        // quiet floor keeps the strip visible
                                        // at rest; pow fattens the mid-range
                                        height: 4 + Math.pow(v, 0.75) * 30
                                        radius: 1.5
                                        color: Services.Colors.accent
                                        // depth: older samples fade leftward
                                        opacity: 0.3 + 0.7 * (index / 23)
                                        Behavior on height {
                                            NumberAnimation {
                                                duration: Services.Motion.short1
                                                easing.type: Easing.BezierSpline
                                                easing.bezierCurve: Services.Motion.emphasizedDecelerate
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ——— transcribing: whisper is chewing ———
                    Column {
                        visible: win.phase === "transcribing"
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 5

                        Text {
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                            font.bold: true
                            color: Services.Colors.accent
                            text: "Transcribing…"
                        }
                        DriftDots { running: win.phase === "transcribing" }
                    }

                    // ——— thinking: what was heard + drifting dots ———
                    Row {
                        visible: win.phase === "thinking"
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 12

                        Text {
                            width: 210
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                            color: Services.Colors.text
                            text: win.note !== "" ? "“" + win.note + "”" : "Waiting…"
                        }
                        DriftDots { running: win.phase === "thinking" }
                    }

                    // ——— speaking: Piper reads the reply, waves emit ———
                    Row {
                        visible: win.phase === "speaking"
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 10

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            font.family: Services.Fonts.family
                            font.pixelSize: 12
                            font.bold: true
                            color: Services.Colors.accent
                            text: "Speaking"
                        }
                        SpeakBars { running: win.phase === "speaking" }
                    }

                    // ——— miss: script clears this after a beat ———
                    Text {
                        visible: win.phase === "miss"
                        anchors.verticalCenter: parent.verticalCenter
                        font.family: Services.Fonts.family
                        font.pixelSize: 12
                        color: Services.Colors.textMuted
                        text: "Didn't catch that"
                    }
                }
            }
        }
    }

    // three dots on a staggered drift — the "something is thinking" read
    component DriftDots: Row {
        id: dots
        property bool running: false
        property real t: 0
        spacing: 5
        Timer {
            interval: 60; repeat: true; running: dots.running
            onTriggered: dots.t += 0.28
        }
        Repeater {
            model: 3
            delegate: Rectangle {
                required property int index
                width: 6; height: 6; radius: 3
                color: Services.Colors.accent
                opacity: 0.25 + 0.7 * Math.abs(Math.sin(dots.t * 3 - index * 1.9))
                scale: 0.7 + 0.3 * Math.abs(Math.sin(dots.t * 3 - index * 1.9))
            }
        }
    }

    // the reply leaving the blob — three bars pulsing like a speaker icon
    component SpeakBars: Row {
        id: bars
        property bool running: false
        property real t: 0
        spacing: 4
        height: 26
        Timer {
            interval: 33; repeat: true; running: bars.running
            onTriggered: bars.t += 0.42
        }
        Repeater {
            model: 3
            delegate: Rectangle {
                required property int index
                width: 3.5; radius: 2
                anchors.verticalCenter: parent.verticalCenter
                height: 7 + 15 * Math.abs(Math.sin(bars.t * 2.2 + index * 1.7))
                color: Services.Colors.accent
            }
        }
    }
}
