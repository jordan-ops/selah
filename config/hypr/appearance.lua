-----------------------
---- LOOK AND FEEL ----
-----------------------

-- Refer to https://wiki.hypr.land/Configuring/Basics/Variables/
hl.config({
    general = {
        gaps_in  = 5,
        gaps_out = 20,

        border_size = 2,

        col = {
            active_border   = { colors = {"rgba(33ccffee)", "rgba(00ff99ee)"}, angle = 45 },
            inactive_border = "rgba(595959aa)",
        },

        -- Set to true to enable resizing windows by clicking and dragging on borders and gaps
        resize_on_border = false,

        -- Please see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Tearing/ before you turn this on
        allow_tearing = false,

        layout = "scrolling",
    },

    decoration = {
        rounding       = 10,
        rounding_power = 2,

        -- Change transparency of focused and unfocused windows
        active_opacity   = 1.0,
        inactive_opacity = 1.0,

        shadow = {
            enabled      = true,
            range        = 4,
            render_power = 3,
            color        = 0xee1a1a1a,
        },

        -- Matched to the lockscreen's wash (quickshell's lock/LockBackdrop
        -- runs the wallpaper through MultiEffect at blur 1.0 / blurMax 128 /
        -- multiplier 1.25). size 3 / passes 1 was the mildest thing that
        -- still read as blur — it dimmed, it didn't frost, so a video behind
        -- a transparent panel still fought the text on top of it. 8/3 is
        -- Hyprland's stock size with real passes behind it: the backdrop
        -- collapses into a colour field and the labels stay labels.
        -- passes is what keeps size 8 from looking blocky (wiki: raise it
        -- whenever size goes up); it costs GPU only where something is
        -- actually transparent, and nothing in the default config is.
        -- 2026-10 heat retune: 8/3 ran three full gaussian sweeps over the
        -- bar + widget strips every time those surfaces damaged, which on
        -- the HD 4600 meant continuous max-clock GPU. 4/1 is one cheaper
        -- sweep — still frosts, a fraction of the fill rate. popups off:
        -- their own words below called popups the worst offender, and a
        -- menu over video isn't worth a per-frame blur.
        -- 2026-10-09 (game-mode gap analysis): with Panel transparency at
        -- 0 the pill is OPAQUE, so the qs-glass frost in rules.lua works
        -- invisibly — every frame of damage anywhere under the bar's
        -- 1920x560 slab re-runs the gaussian pass behind pixels no eye
        -- can see. Measured idle with a steady app-damage stream: blur
        -- on pinned the iGPU at 1269/1300MHz (game mode: 407MHz); blur
        -- off alone dropped it to ~500 with zero visible change. So the
        -- master switch now defaults OFF — the frost recipe below is
        -- kept for the moment someone raises Panel transparency or flips
        -- Settings ▸ Appearance ▸ Blur effects back on, which is the
        -- only time any of this is visible. Windows are opacity 1.0 and
        -- blur:popups is off, so nothing else ever fed this switch.
        blur = {
            enabled   = false,
            size      = 4,
            passes    = 1,
            vibrancy  = 0.1696,

            popups    = false,
        },
    },

    animations = {
        enabled = true,
    },
})

-- Default curves and animations, see https://wiki.hypr.land/Configuring/Advanced-and-Cool/Animations/
hl.curve("easeOutQuint",   { type = "bezier", points = { {0.23, 1},    {0.32, 1}    } })
hl.curve("easeInOutCubic", { type = "bezier", points = { {0.65, 0.05}, {0.36, 1}    } })
hl.curve("linear",         { type = "bezier", points = { {0, 0},       {1, 1}       } })
hl.curve("almostLinear",   { type = "bezier", points = { {0.15, 0},    {0.75, 1}    } })
hl.curve("quick",          { type = "bezier", points = { {0.15, 0},    {0.1, 1}     } })

-- M3 Expressive easing set — m3.material.io/styles/motion (specs), the
-- same curves services/Motion.qml carries in the shell so both halves of
-- the desktop move identically:
--   enter      = emphasized decelerate (0.05, 0.7, 0.1, 1)
--   exit       = emphasized accelerate  (0.3, 0, 0.8, 0.15)
--   begin/end  = standard in+out (0.2, 0, 0, 1)
-- (M3's emphasized begin/end path is two cubic segments — only Android's
--  interpolator carries it; the standard in+out cubic stands in here.)
hl.curve("m3Decelerate",   { type = "bezier", points = { {0.05, 0.7},  {0.1, 1}     } })
hl.curve("m3Accelerate",   { type = "bezier", points = { {0.3, 0},     {0.8, 0.15}  } })
hl.curve("m3Standard",     { type = "bezier", points = { {0.2, 0},     {0, 1}       } })

-- hyprdots' two extra curves (its md3_standard / md3_decel / md3_accel are
-- byte-identical to m3Standard / m3Decelerate / m3Accelerate above, so only
-- the genuinely new ones are added):
--   glide     sharp attack, long tail — borders, switches
--   closeSoft soft ease-out with no bounce — window closes, fade-outs
hl.curve("glide",          { type = "bezier", points = { {0.10, 0.90}, {0.15, 1.00} } })
hl.curve("closeSoft",      { type = "bezier", points = { {0.32, 0.00}, {0.18, 1.00} } })

-- Springs. ζ (damping ratio) = dampening / (2·√(stiffness·mass)).
--
-- 2026-11: replaced easy / m3Bounce / m3BounceWide with hyprdots' isle
-- family — verified genuinely better, not just slower: ζ0.86/0.96/1.00 vs
-- our old 0.78/0.76/0.85, so overshoot drops from 1.9–2.6% to ~0.5%/0/0
-- while settling 457–512ms → 467/457/525ms (same tempo, ~4× less wobble).
-- hyprdots derives each spring from a response/damping-ratio pair
-- (w = 2π/response; stiffness = w²; dampening = 2·ζ·w), then we stretch
-- 1.5× in time (stiffness ÷2.25, dampening ÷1.5 — same retune as
-- Motion.qml's springs and the speeds below, so shell and compositor
-- keep moving as one system; ζ is unchanged by the stretch):
--   isle       hyprdots 0.42s / ζ0.86 → 99.47 / 17.15 — move/resize
--              generic, velocity-retargeting, ~0.5% overshoot
--   isleCalm   hyprdots 0.46s / ζ0.96 → 82.92 / 17.48 — window/layer
--              opens: kisses the mark and stops, no bounce
--   isleGlide  hyprdots 0.55s / ζ1.00 → 58.00 / 15.23 — critically
--              damped workspace slides: dead straight, no edge sliver
--              (the old ζ0.85 kiss-past was ≈16px at 2560w)
hl.curve("isle",           { type = "spring", mass = 1, stiffness = 99.47,  dampening = 17.15 })
hl.curve("isleCalm",       { type = "spring", mass = 1, stiffness = 82.92,  dampening = 17.48 })
hl.curve("isleGlide",      { type = "spring", mass = 1, stiffness = 58.00,  dampening = 15.23 })

-- Motion copied from hyprdots' animation set (2026-11), with OUR styles
-- kept: windows and workspaces still SLIDE in unison (the M3 carousel/tab
-- rule) instead of hyprdots' popin 86%/93% and slidefade 12%. Curves and
-- speed ratios are theirs — md3_decel / md3_accel / md3_standard are
-- byte-identical to m3Decelerate / m3Accelerate / m3Standard above, and
-- glide / closeSoft were added above — and every speed below is theirs
-- ×1.5 to keep the pairing with Motion.qml durationScale 1.5 (both
-- halves run 1.5× their nominal).
-- speed is ds: 1ds = 100ms, and it only times BEZIER curves — springs
-- ignore it entirely (hyprutils advanceSpring() steps by real elapsed
-- time until the spring settles), so spring speeds are documentation.
-- `windows`/`windowsMove` keep the velocity-retargeting generic isle;
-- `fade`/`layers` stay on m3Standard as fallbacks for the leaves not
-- listed (fadeGlow, fadeDpms).
hl.animation({ leaf = "global",        enabled = true,  speed = 15,    bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 13.5,  bezier = "glide" })
hl.animation({ leaf = "borderangle",   enabled = true,  speed = 90,    bezier = "linear" })

-- windows: opens ride isleCalm (ζ0.96 — lands and stays) and still slide
-- in as one; closes ease out on closeSoft (no bounce, hyprdots' whole
-- exit language is "soft close")
hl.animation({ leaf = "windows",       enabled = true,  speed = 7.05,  spring = "isle" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 7.5,   spring = "isleCalm",    style = "slide" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 8.4,   bezier = "closeSoft",   style = "slide" })
hl.animation({ leaf = "windowsMove",   enabled = true,  speed = 7.05,  spring = "isle" })

-- fades: enter on M3 decelerate, exit on closeSoft, switches/geometry on
-- glide, popups accelerate out
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 6,     bezier = "m3Decelerate" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 7.5,   bezier = "closeSoft" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 4.5,   bezier = "m3Standard" })
hl.animation({ leaf = "fadeSwitch",    enabled = true,  speed = 6,     bezier = "glide" })
hl.animation({ leaf = "fadeShadow",    enabled = true,  speed = 7.5,   bezier = "m3Decelerate" })
hl.animation({ leaf = "fadeDim",       enabled = true,  speed = 6,     bezier = "m3Decelerate" })
hl.animation({ leaf = "fadePopupsIn",  enabled = true,  speed = 4.5,   bezier = "m3Decelerate" })
hl.animation({ leaf = "fadePopupsOut", enabled = true,  speed = 3,     bezier = "m3Accelerate" })

-- layers: enter on the isleCalm spring with our fade style (hyprdots
-- pops in from 92%), exit accelerates out
hl.animation({ leaf = "layers",        enabled = true,  speed = 5.72,  bezier = "m3Standard" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 7.5,   spring = "isleCalm",    style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 4.5,   bezier = "m3Accelerate", style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 4.5,   bezier = "m3Decelerate" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 3,     bezier = "m3Accelerate" })

-- workspaces: lateral motion = M3's carousel/tab rule — slide in unison,
-- no fade, one critically-damped spring (isleGlide, ζ1.00) on both sides
-- of the switch so old and new move as one with zero overshoot
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 10.05, spring = "isleGlide",   style = "slide" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 10.05, spring = "isleGlide",   style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 10.05, spring = "isleGlide",   style = "slide" })
hl.animation({ leaf = "specialWorkspaceIn",  enabled = true, speed = 10.05, spring = "isleGlide", style = "slidevert" })
hl.animation({ leaf = "specialWorkspaceOut", enabled = true, speed = 6,     bezier = "m3Accelerate", style = "slidevert" })

hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7.5,   spring = "isleCalm" })
