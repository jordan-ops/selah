// The flip clock screensaver — Fliqlo's split-flap look, quickshell's
// process (Settings ▸ Lock screen ▸ Screensaver style = "Flip clock",
// the default). Reference: fliqlo.com + github.com/phaselden/FlipIt.
// WHY THIS EXISTS: the pipes.sh runner needs a terminal per monitor and
// repaints a fullscreen surface at 25 fps — ~0.9 of a core while it
// runs. This surface paints ONCE and then nothing: the time comes from
// the Time singleton the bar already ticks (its minute-precision
// SystemClock — this file adds NO timer of its own), the window is
// static between flips, and exactly one card animates for ~340 ms each
// minute. At rest the cost is a mapped layer surface with no repaints.
// DISMISSAL, both belts: any input anywhere resets ext-idle and
// Screensaver's onIsIdleChanged dismisses (the idle-launched path);
// a key or pointer movement ON the surface dismisses a manually
// launched clock, which never had an idle edge to ride. Keys are
// accepted, so a press lands here and never in the window behind.

import "./services" as Services
import QtQuick
import Quickshell
import Quickshell.Wayland

// GEOMETRY follows the FlipIt screenshot: two cards — hours, minutes —
// split by a seam GAP (a real strip of black cut through the card AND
// the digits, the same width as the space between the cards, so the
// cut reads as one idea across the whole clock), accent-colored
// numerals in a FIXED monospace — deliberately never the shell font,
// whose metrics could come back with uneven digits and unbalance the
// cards. No colon, no date: Fliqlo shows the clock and nothing else.
Variants {
    model: Quickshell.screens

    PanelWindow {
        id: win

        required property var modelData
        // Cards sit near-square (FlipIt ≈ 1.03 w/h), the pair a bit
        // under half the screen wide — big across a room, small enough
        // that a 1366-wide external monitor never clips it.
        readonly property real cardH: Math.round(Math.min(height * 0.4, width * 0.245))
        readonly property real cardW: Math.round(cardH * 1.03)
        readonly property real cardGap: Math.round(cardH * 0.04)
        // "hh:mm" — the bar's format (Time's SystemClock, minute
        // precision, already running for the bar; no second clock here)
        readonly property string hhmm: Services.Time.time

        screen: modelData
        visible: Services.Screensaver.internalActive
        color: "#000000"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.layer: WlrLayer.Overlay
        // Exclusive so keystrokes land HERE and are swallowed, never in
        // the window behind the clock. One seat, one focus: with several
        // monitors each surface asks and the compositor grants the
        // newest — dismissal doesn't depend on which won, because any
        // input anywhere resets ext-idle.
        WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        WlrLayershell.namespace: "selah-screensaver"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        Item {
            anchors.centerIn: parent
            width: clockRow.width
            height: win.cardH

            Row {
                id: clockRow

                spacing: win.cardGap

                FlipCard {
                    width: win.cardW
                    height: win.cardH
                    text: win.hhmm.length >= 2 ? win.hhmm.slice(0, 2) : "  "
                }

                FlipCard {
                    width: win.cardW
                    height: win.cardH
                    text: win.hhmm.length === 5 ? win.hhmm.slice(3, 5) : "  "
                }

            }

        }

        // ---- keyboard: ANY key dismisses, accepted so it is swallowed ----
        Item {
            id: keyHandler

            anchors.fill: parent
            focus: win.visible
            onVisibleChanged: {
                if (visible) {
                    forceActiveFocus();
                }
            }
            Keys.onPressed: (event) => {
                Services.Screensaver.dismiss();
                event.accepted = true;
            }
        }

        // ---- pointer: a click dismisses ----
        // Motion deliberately does NOT dismiss from here: the window
        // maps under the possibly-moving cursor, and hover events emit
        // positionChanged on ENTER — a motion listener killed the saver
        // within 500 ms of showing it (verified live). Pointer movement
        // during an idle run is still covered GLOBALLY: ext-idle resets
        // on any motion anywhere and Screensaver's onIsIdleChanged
        // dismisses. What's left here — click + the key handler above —
        // is the manually-launched case, the same set pipes.sh had.
        MouseArea {
            anchors.fill: parent
            onPressed: Services.Screensaver.dismiss()
        }

        // ————— one flap card = two digits, hinged at the seam —————
        // text changes ("34"→"35", "17"→"18") drive the whole flip:
        // the OLD top half falls away (revealing the new top behind
        // it), then the NEW bottom half swings down onto the old one.
        // Both flap glyphs are plain bindings — committed is old until
        // the sequence lands, so there is no imperative state to leak.
        component FlipCard: Item {
            id: fc

            // two digits: "17" hours / "34" minutes
            property string text: "00"
            // what the static bottom half currently draws; flips to the
            // new text only when the animation lands
            property string committed: "00"
            property bool ready: false

            function startFlip() {
                // hidden minute rolls commit silently — no animation
                // for a surface nobody can see (and none for a flip
                // that would have to start from a stale mid-state)
                if (!fc.visible) {
                    fc.committed = fc.text;
                    return ;
                }
                // belt: impossible at minute cadence, but a stuttered
                // restart mid-flip must still land in a consistent state
                if (seq.running) {
                    seq.stop();
                    topFlap.visible = false;
                    botFlap.visible = false;
                    fc.committed = fc.text;
                    return ;
                }
                topFlap.visible = true;
                botFlap.visible = false;
                topFlap.angle = 0;
                botFlap.angle = 90;
                seq.restart();
            }

            Component.onCompleted: {
                fc.committed = fc.text;
                fc.ready = true;
            }
            onTextChanged: {
                if (!fc.ready) {
                    fc.committed = fc.text;
                    return ;
                }
                if (fc.text === fc.committed || fc.text.length !== 2)
                    return ;

                fc.startFlip();
            }

            // stacking order IS the flip order: statics first (painted
            // below), then the bottom flap, then the top flap on top
            CardHalf {
                // new top — revealed by the falling old-top flap
                cardW: fc.width
                cardH: fc.height
                glyph: fc.text
            }

            CardHalf {
                // committed bottom — the bottom flap lands ON this, so
                // it stays visible through phase 2 (no empty frame)
                cardW: fc.width
                cardH: fc.height
                lower: true
                glyph: fc.committed
            }

            CardHalf {
                id: botFlap

                cardW: fc.width
                cardH: fc.height
                lower: true
                visible: false
                glyph: fc.text
            }

            CardHalf {
                id: topFlap

                cardW: fc.width
                cardH: fc.height
                visible: false
                glyph: fc.committed
            }

            SequentialAnimation {
                id: seq

                // falling flap accelerates, landing flap decelerates —
                // ~340 ms total, then this surface is static again
                NumberAnimation {
                    target: topFlap
                    property: "angle"
                    to: -90
                    duration: 170
                    easing.type: Easing.InQuad
                }

                ScriptAction {
                    script: {
                        topFlap.visible = false;
                        botFlap.visible = true;
                    }
                }

                NumberAnimation {
                    target: botFlap
                    property: "angle"
                    from: 90
                    to: 0
                    duration: 170
                    easing.type: Easing.OutQuad
                }

                ScriptAction {
                    script: {
                        botFlap.visible = false;
                        fc.committed = fc.text;
                    }
                }

            }

        }

        // ————— half a card: a full-card view clipped to its own half —————
        // Background and glyph are drawn at FULL card size and offset
        // into the half, so top and bottom register pixel-perfect (a
        // half-sized background would round the seam corners). The clip
        // stops `gap`/2 short of the seam — a real strip of black
        // THROUGH the card AND the digits, the same width as the space
        // between the two cards — instead of a line drawn on top of
        // them. `angle` is what the flip animates: the rotation origin
        // sits ON the hinge (bottom edge for a top half, top edge for
        // a bottom one), which is why lower halves hinge at their top.
        component CardHalf: Item {
            id: hg

            property string glyph: "00"
            property real cardW: 0
            property real cardH: 0
            property bool lower: false
            property real angle: 0
            // the seam strip — deliberately identical to the gap
            // BETWEEN the cards (0.04 × height): one black width, one
            // gesture, the clock reads as cut from a single piece
            readonly property real gap: Math.round(hg.cardH * 0.04)
            // where the card's own top edge sits in this half's coords
            readonly property real cardTop: hg.lower ? -(hg.cardH / 2 + hg.gap / 2) : 0

            width: hg.cardW
            height: hg.cardH / 2 - hg.gap / 2
            y: hg.lower ? hg.cardH / 2 + hg.gap / 2 : 0
            clip: true

            Rectangle {
                // the whole card, shifted so this half sees its portion
                width: hg.cardW
                height: hg.cardH
                y: hg.cardTop
                radius: Math.round(hg.cardH * 0.09)
                color: "#101010"
            }

            Text {
                width: hg.cardW
                height: hg.cardH
                y: hg.cardTop
                text: hg.glyph
                // the shell's accent, like every other accent surface
                // here — re-themes live on every theme switch
                color: Services.Colors.accent
                // FIXED, deliberately not Services.Fonts: the saver is
                // a fixed appliance face, immune to set-font.sh.
                // Archivo Black — picked by rendering candidates
                // (Anton, Archivo Black) against Fliqlo's own promo
                // shot: the wide slot-counter 0s and heavy flat cuts
                // match the original closest among OFL faces, and its
                // figures share one width so cards stay even. The TTF
                // ships with the repo (config/quickshell/fonts/,
                // linked into ~/.local/share/fonts by install.sh) so
                // the clock never falls back to default sans.
                font.family: "Archivo Black"
                // single-weight family — Normal avoids a synthetic bold
                font.weight: Font.Normal
                // base = full card height, deliberately too wide: Fit
                // then scales DOWN to the card box for any family —
                // never depends on up-scaling behaviour
                font.pixelSize: hg.cardH
                fontSizeMode: Text.Fit
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                antialiasing: true
            }

            transform: Rotation {
                origin.x: hg.width / 2
                origin.y: hg.lower ? 0 : hg.height
                angle: hg.angle

                axis {
                    x: 1
                    y: 0
                    z: 0
                }

            }

        }

    }

}
