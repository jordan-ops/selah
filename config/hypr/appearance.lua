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

-- Springs. ζ (damping ratio) = dampening / (2·√(stiffness·mass)):
--   easy         ζ0.78 — move/resize: velocity-retargeting
--   m3Bounce     ζ0.76 → ~2.6% overshoot — window slides kiss past their
--                mark and settle back (M3E spatial springs bounce into
--                place); overshoot is proportional to travel, and window
--                travel is monitor-scale, so this stays ~2.6%
--   m3BounceWide ζ0.85 → ~0.6% overshoot — a workspace slide crosses the
--                whole monitor; at 3% an overshoot would uncover an ~80px
--                edge sliver for a few frames, so this stays gentle
--                (≈16px at 2560w) while still reading as a bounce
-- 2026-09 retune ("animations too fast"): stiffness ÷2.25, dampening ÷1.5
-- keeps every ζ (so overshoot px is unchanged) while stretching each
-- spring 1.5× in time — matches Motion.qml durationScale 1.5, so shell
-- and compositor slow down as one system.
hl.curve("easy",           { type = "spring", mass = 1, stiffness = 105.83, dampening = 16.14 })
hl.curve("m3Bounce",       { type = "spring", mass = 1, stiffness = 105.83, dampening = 15.63 })
hl.curve("m3BounceWide",   { type = "spring", mass = 1, stiffness = 105.83, dampening = 17.49 })

-- Motion per the M3 specs + M3E springs: window/workspace transitions
-- SLIDE (no more pop-in / fade). Spatial ENTERS ride the bounce springs —
-- they overshoot their mark and settle back (M3 Expressive: "the physics
-- system is replacing the previous system based on easing and duration",
-- spatial springs overshoot to add bounce). EXITS still accelerate out
-- with no bounce, effects (fade/layers) keep the bezier pairs, and
-- in-screen changes ride the standard curve. speed is ds: 1ds = 100ms
-- (springs time themselves; speed stays as fallback/docs). `windows`
-- itself keeps `easy` — move/resize is velocity-retargeted spring motion.
-- Every speed below is ×1.5 since 2026-09 (same retune as the springs and
-- Motion.qml durationScale — "animations too fast"); zoomFactor is exempt
-- (its 7ds is already a deliberate slow zoom).
hl.animation({ leaf = "global",        enabled = true,  speed = 15,    bezier = "default" })
hl.animation({ leaf = "border",        enabled = true,  speed = 8.09,  bezier = "m3Standard" })
hl.animation({ leaf = "windows",       enabled = true,  speed = 10,    spring = "easy" })
hl.animation({ leaf = "windowsIn",     enabled = true,  speed = 12,    spring = "m3Bounce",      style = "slide" })
hl.animation({ leaf = "windowsOut",    enabled = true,  speed = 3,     bezier = "m3Accelerate",   style = "slide" })
hl.animation({ leaf = "fadeIn",        enabled = true,  speed = 12,    bezier = "m3Decelerate" })
hl.animation({ leaf = "fadeOut",       enabled = true,  speed = 3,     bezier = "m3Accelerate" })
hl.animation({ leaf = "fade",          enabled = true,  speed = 4.5,   bezier = "m3Standard" })
hl.animation({ leaf = "layers",        enabled = true,  speed = 5.72,  bezier = "m3Standard" })
hl.animation({ leaf = "layersIn",      enabled = true,  speed = 6,     bezier = "m3Decelerate",   style = "fade" })
hl.animation({ leaf = "layersOut",     enabled = true,  speed = 3,     bezier = "m3Accelerate",   style = "fade" })
hl.animation({ leaf = "fadeLayersIn",  enabled = true,  speed = 2.69,  bezier = "m3Decelerate" })
hl.animation({ leaf = "fadeLayersOut", enabled = true,  speed = 2.09,  bezier = "m3Accelerate" })
-- workspaces: lateral motion = M3's carousel/tab rule — slide in unison,
-- no fade, same spring on both sides of the switch so old and new move as
-- one; m3BounceWide (ζ0.85) kisses ~16px past at 2560w and settles — a
-- bounce without uncovering the monitor edge.
hl.animation({ leaf = "workspaces",    enabled = true,  speed = 3,    spring = "m3BounceWide",   style = "slide" })
hl.animation({ leaf = "workspacesIn",  enabled = true,  speed = 3,    spring = "m3BounceWide",   style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true,  speed = 3,    spring = "m3BounceWide",   style = "slide" })
hl.animation({ leaf = "zoomFactor",    enabled = true,  speed = 7,    bezier = "m3Standard" })
