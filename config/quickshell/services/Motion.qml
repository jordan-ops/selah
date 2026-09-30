pragma Singleton

import Quickshell
import QtQuick

// Material 3 Expressive motion tokens — m3.material.io/styles/motion
//
// M3 splits motion into two families, and this file implements both:
//
//   SPATIAL (size / position / scale) → real spring physics.
//     Qt SpringAnimation parameter pairs below were measured empirically on
//     this machine's Qt (offscreen harness, 0→100 step, reporting overshoot%
//     and time-to-within-±0.5%): `damping` behaves like a damping ratio where
//     LOWER = faster to rest (Qt's docs were right), `spring` is stiffness
//     (the documented 0–5 "useful range" is conservative — 6–21 lands in
//     usable UI speeds), and overshoot rises with stiffness and falls with
//     damping. Every pair below is MEASURED on this machine's Qt 6 (test
//     harness /tmp/opencode/springtest/tests — 0→100 step, 5ms sampling,
//     qmltestrunner junit output) and tuned to M3 Expressive's schemes:
//     the expressive motion scheme OVERSHOOTS final values to add bounce
//     (spatial springs bounce into place), while effects never bounce.
//     Retuned 1.5× slower to match durationScale below — same overshoot
//     bands, longer settle (parentheses = the pre-retune pair and settle):
//       default: spring 6 / 0.42    → ~2.3% overshoot, 325ms settle (was 30/0.8,   205ms — structural morphs)
//       fast:    spring 18 / 0.58   → ~7%   overshoot, 175ms settle (was 40/0.8,   118ms — small/fast components)
//       slow:    spring 11 / 0.78   → ~0%   overshoot, 345ms settle (was 15/0.78,  200ms — large moves stay calm)
//       bounce:  spring 19 / 0.53   → ~12%  overshoot, 235ms settle (was 35/0.7,   143ms — interactive travels)
//       pop:     spring 21 / 0.47   → ~20%  overshoot, 270ms settle (was 45/0.65,  147ms — press→release scale)
//     Springs also retarget with velocity — flipping pill modes mid-morph
//     carries momentum instead of restarting from zero. That's the whole
//     point of Expressive spatial motion.
//
//   EFFECTS (opacity / color) → never overshoot (M3 effects springs are ζ=1,
//     critically damped). Qt can't reach that speed without overshooting
//     (spring 20 / damping 1.0 settles ~400ms) and ColorAnimation can't spring
//     at all — so effects use the EXACT M3 emphasized cubic-beziers
//     (Easing.BezierSpline carries arbitrary control points, so these are the
//     spec curves, not approximations) with durations derived from M3's
//     effects spring stiffnesses (critically-damped settle ≈ 6.6/√k):
//       k=3800 → ~105ms → effectsFast   k=1600 → ~165ms → effects
//       k=800  → ~235ms → effectsSlow
//     (those are spec values; the tokens run them ×durationScale, so
//     effects take 150 / 225 / 300ms at the current 1.5)
//     A ζ=1 spring and an emphasized decelerate curve are the same shape.
//
// quickshell also ships standalone EasingCurve objects (valueAt/interpolate)
// for script-driven motion outside Behaviors — same curve data lives here.
//
// PAIRS + PATTERNS (m3.material.io/styles/motion/overview/specs) — the
// suggested duration pairs are the tokens below (emphasizedEnter/Exit,
// standardBeginEnd/Enter/Exit); when a surface or list item appears or
// disappears, pair emphasizedEnter with emphasizedDecelerate and
// emphasizedExit with emphasizedAccelerate — never cross the pairs. The
// movement patterns themselves:
//   • enter/exit the screen → emphasized decelerate 400 / accelerate 200
//   • forward/back navigation → partial slide + fade together (shared
//     axis; content never travels the full screen width)
//   • lateral motion (carousels, tabs, workspaces) → slide in unison,
//     no fade — both sides share one curve so they read as one object
//   • begin/end on screen (in-place value changes) → 500 emphasized
//
// BOUNCE (M3E "expressive" scheme): spatial enters and interactive travels
// ride the measured springs above (bounce / pop, plus default's light 2%
// overshoot) — spatial springs overshoot into place; fades and colors keep
// the bezier pairs, exits never bounce. ~/.config/hypr/appearance.lua
// mirrors the curves AND the bounce idea as compositor springs (m3Bounce /
// m3BounceWide on windowsIn / workspaces, slide styles), so shell and
// Hyprland move as one system.
Singleton {
    id: root

    // ---------------- settings.json knobs (settings app → Animations tab) ----------------
    // motion.enabled    — false = reduced motion: duration tokens drop to 0
    //                     (every NumberAnimation snaps) and springs take the
    //                     measured instant pair (50/1: 65ms settle, 0%
    //                     overshoot — spring 0 sticks at the start, so a
    //                     SpringAnimation can't be truly "off").
    // motion.speedScale — 0.5–1.5, 1 = this file's tuned feel (default).
    //                     Durations run 1.5/scale (1.5× = faster), springs
    //                     scale stiffness ×scale², damping ×scale — the
    //                     ζ-preserving retune math appearance.lua documents.
    //                     Measured at both ends + middle (tst_anim2): the
    //                     overshoot bands hold; 2× inflates them ~2×, so
    //                     the knob stops at 1.5.
    readonly property bool motionOn: {
        const v = Settings.values["motion.enabled"]
        return !(v === false || v === "false")
    }
    readonly property real speedScale: {
        const v = Settings.values["motion.speedScale"]
        const n = v === undefined ? 1 : Number(v)
        return isNaN(n) ? 1 : Math.max(0.5, Math.min(1.5, n))
    }

    // ---------------- duration scale: md.sys.motion.duration.* ----------------
    // ONE knob retimes every duration token: M3 spec value × durationScale.
    // "the animations are too fast" → 1.5 (2026-09). Springs are tuned
    // separately (measured pairs at the bottom), not derived from this.
    readonly property real durationScale: motionOn ? 1.5 / speedScale : 0

    readonly property int short1: Math.round(50 * durationScale)
    readonly property int short2: Math.round(100 * durationScale)
    readonly property int short3: Math.round(150 * durationScale)
    readonly property int short4: Math.round(200 * durationScale)
    readonly property int medium1: Math.round(250 * durationScale)
    readonly property int medium2: Math.round(300 * durationScale)
    readonly property int medium3: Math.round(350 * durationScale)
    readonly property int medium4: Math.round(400 * durationScale)
    readonly property int long1: Math.round(450 * durationScale)
    readonly property int long2: Math.round(500 * durationScale)
    readonly property int long3: Math.round(550 * durationScale)
    readonly property int long4: Math.round(600 * durationScale)
    readonly property int extraLong1: Math.round(700 * durationScale)
    readonly property int extraLong2: Math.round(800 * durationScale)
    readonly property int extraLong3: Math.round(900 * durationScale)
    readonly property int extraLong4: Math.round(1000 * durationScale)

    // ---------------- suggested duration pairs (M3 motion patterns) ----------------
    readonly property int emphasizedBeginEnd: long2   // spec 500 → 750 — emphasized in+out
    readonly property int emphasizedEnter: medium4    // spec 400 → 600 — decelerate (entrances)
    readonly property int emphasizedExit: short4      // spec 200 → 300 — accelerate (exits)
    readonly property int standardBeginEnd: medium2   // spec 300 → 450 — standard in+out
    readonly property int standardEnter: medium1      // spec 250 → 375
    readonly property int standardExit: short4        // spec 200 → 300

    // effects (opacity/color) durations derived from M3 effects springs
    // (spec k gives 105/165/235ms; the tokens carry durationScale on top)
    readonly property int effectsFast: short2         // 150
    readonly property int effects: short3             // 225
    readonly property int effectsSlow: short4         // 300

    // ---------------- exact M3 cubic-beziers, used via Easing.BezierSpline ----------------
    // usage in any animation:
    //   easing.type: Easing.BezierSpline
    //   easing.bezierCurve: Services.Motion.emphasizedDecelerate
    readonly property var standardCurve: [0.2, 0, 0, 1, 1, 1]
    readonly property var standardDecelerate: [0, 0, 0, 1, 1, 1]
    readonly property var standardAccelerate: [0.3, 0, 1, 1, 1, 1]
    readonly property var emphasizedDecelerate: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var emphasizedAccelerate: [0.3, 0, 0.8, 0.15, 1, 1]
    // Android's emphasized path — two cubic segments, BezierSpline supports
    // multi-segment lists (last point must be 1,1)
    readonly property var emphasizedCurve: [0.05, 0, 0.133333, 0.06, 0.166666, 0.4, 0.208333, 0.82, 0.25, 1, 1, 1]

    // ---------------- spatial springs → Qt SpringAnimation (measured values) ----------------
    // usage: SpringAnimation { spring: Services.Motion.spatialSpring; damping: Services.Motion.spatialDamping }
    // overshoot/settle measured at 5ms sampling; re-run the harness to retune
    // The pairs carry their measured %/ms comments below at speedScale=1;
    // motion.speedScale retimes them ζ-preserving (stiffness ×s², damping
    // ×s — the same retune math appearance.lua documents for its own
    // springs), and motion.enabled = false snaps every pair to the
    // measured instant pair (50/1: 65ms, 0% overshoot) so reduced motion
    // keeps zero bounce.
    readonly property int spatialSpring: motionOn ? Math.round(6 * speedScale * speedScale) : 50
    readonly property real spatialDamping: motionOn ? 0.42 * speedScale : 1
    readonly property int spatialFastSpring: motionOn ? Math.round(18 * speedScale * speedScale) : 50
    readonly property real spatialFastDamping: motionOn ? 0.58 * speedScale : 1
    readonly property int spatialSlowSpring: motionOn ? Math.round(11 * speedScale * speedScale) : 50
    readonly property real spatialSlowDamping: motionOn ? 0.78 * speedScale : 1
    // M3E expressive: interactive travels — switch throws, list enters,
    // page slides, indicator slides — reads as a clear bounce
    readonly property int bounceSpring: motionOn ? Math.round(19 * speedScale * speedScale) : 50
    readonly property real bounceDamping: motionOn ? 0.53 * speedScale : 1
    // press→release scale pops: the delta is tiny (e.g. 0.94→1.0), so the
    // overshoot band must be large for the bounce to be visible at all
    readonly property int popSpring: motionOn ? Math.round(21 * speedScale * speedScale) : 50
    readonly property real popDamping: motionOn ? 0.47 * speedScale : 1

    // ---------------- staggered entrances (M3 grids/lists cascade in) ----------------
    readonly property int staggerStep: Math.round(40 * durationScale)   // 60
    function staggerDelay(index) {
        return Math.min(index, 5) * staggerStep
    }
}
