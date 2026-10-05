--------------------------------
---- WINDOWS AND WORKSPACES ----
--------------------------------

-- See https://wiki.hypr.land/Configuring/Basics/Window-Rules/
-- and https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/

-- Example window rules that are useful

local suppressMaximizeRule = hl.window_rule({
	-- Ignore maximize requests from all apps. You'll probably like this.
	name = "suppress-maximize-events",
	match = { class = ".*" },

	suppress_event = "maximize",
})
-- suppressMaximizeRule:set_enabled(false)

-- Ref https://wiki.hypr.land/Configuring/Basics/Workspace-Rules/
-- "Smart gaps" / "No gaps when only"
-- uncomment all if you wish to use that.
-- hl.workspace_rule({ workspace = "w[tv1]", gaps_out = 0, gaps_in = 0 })
-- hl.workspace_rule({ workspace = "f[1]",   gaps_out = 0, gaps_in = 0 })
-- hl.window_rule({
--     name  = "no-gaps-wtv1",
--     match = { float = false, workspace = "w[tv1]" },
--     border_size = 0,
--     rounding    = 0,
-- })
-- hl.window_rule({
--     name  = "no-gaps-f1",
--     match = { float = false, workspace = "f[1]" },
--     border_size = 0,
--     rounding    = 0,
-- })

hl.window_rule({
	-- Fix some dragging issues with XWayland
	name = "fix-xwayland-drags",
	match = {
		class = "^$",
		title = "^$",
		xwayland = true,
		float = true,
		fullscreen = false,
		pin = false,
	},

	no_focus = true,
})

-- Every floating window maps centered — terminals floated with Super+V,
-- dialogs, the tensaku editor. (Map-time only: the Super+V bind re-centers
-- on float toggle, since window rules don't re-apply then.)
hl.window_rule({
	name = "center-floats",
	match = { float = true },
	center = true,
})

-- DEFAULT SIZE FOR ALL FLOATING WINDOWS — cliamp's measurements (1234x721
-- on the 1920x1080 eDP-1), adopted as the session default. `size` only
-- acts on floating windows, so tiled windows are untouched; anything that
-- maps floating (cliamp, mpv, dialogs, ...) opens at this size instead of
-- its own preferred geometry.
-- Matched on class, NOT on `float = true`: static effects are matched
-- before a window's float state is set, so a float-matched rule never
-- fires at map time (verified on 0.56.2 — it silently does nothing).
-- Map-time only: Super+V in binds.lua applies the same size to windows
-- floated mid-session.
hl.window_rule({
	name = "default-float-size",
	match = { class = ".*" },
	size = { 1234, 721 },
})

-- tensaku image editor — belt-and-suspenders float+center (the editor
-- self-floats and center-floats above catches it; this covers builds
-- that don't. Observed app_ids: "tensaku" (editor), "GTK Application"
-- (bare launcher — deliberately NOT matched, too broad).
hl.window_rule({
	name = "tensaku-editor",
	match = { class = "^(tensaku|dev\\.tensaku\\.Tensaku)$" },
	float = true,
	center = true,
})

hl.window_rule({
	name = "megasync",
	match = { class = "^megasync$" },
	float = true,
	center = true,
})
-- mpv — always floats. Matched on class "^mpv$" so it catches both the
-- native Wayland app_id and the XWayland class. Centering comes free from
-- "center-floats" above (match = { float = true }), so no explicit center
-- here. Leave this on: a tiled player only sizes itself to the video after
-- the first frame, so it maps at 1x1 and then never re-tiles.
hl.window_rule({
	name = "mpv-float",
	match = { class = "^mpv$" },
	float = true,
})

-- cliamp — retro terminal music player: floats like mpv (a fixed-size TUI
-- player, not a document to tile). Title match, not class: it runs inside
-- foot and foot IS the daily terminal, so a class rule would float every
-- terminal in the session. The launcher mints that title itself —
-- `foot -T cliamp` in Launcher.qml's Terminal=true wrapper — so the rule
-- holds from the first frame even if the TUI never paints its own.
-- Centering comes free from "center-floats" above.
hl.window_rule({
	name = "cliamp-float",
	match = { title = ".*cliamp.*" },
	float = true,
})

-- The launcher's Delete-key uninstall reopens itself under foot with a
-- title like "Uninstall Foot" — float+center it like the dialog it is.
-- Matched on TITLE, not class: foot IS the daily terminal
-- (programs.lua), so a class rule would float every terminal.
hl.window_rule({
	name = "uninstall-terminal",
	match = { title = "^Uninstall.*" },
	float = true,
	center = true,
})

-- Layer rules also return a handle.
-- local overlayLayerRule = hl.layer_rule({
--     name  = "no-anim-overlay",
--     match = { namespace = "^myoverlay$" },
--     no_anim = true,
-- })
-- overlayLayerRule:set_enabled(false)

-- Hyprland-run windowrule
hl.window_rule({
	name = "move-hyprland-run",
	match = { class = "hyprland-run" },

	move = "20 monitor_h-120",
	float = true,
})

-- The Omarchy screensaver (ported to ~/.local/bin/omarchy-launch-screensaver):
-- a fullscreen float on its own special workspace. The launcher passes each
-- monitor's workspace through the exec tag; this class rule is the fallback
-- when a terminal maps again as it closes — out of sight, where its
-- fullscreen rule can't take over a normal workspace (same rules omarchy
-- ships in default/hypr/apps/system.lua).
hl.window_rule({
	name = "screensaver",
	match = { class = "org.omarchy.screensaver" },

	fullscreen = true,
	float = true,
	animation = "slide",
	workspace = "special:screensaver silent",
})
