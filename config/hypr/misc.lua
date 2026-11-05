----------------
----  MISC  ----
----------------

hl.config({
	misc = {
		force_default_wallpaper = 0, -- Set to 0 or 1 to disable the anime mascot wallpapers
		disable_hyprland_logo = true, -- If true disables the random hyprland logo / anime girl background. :(
	},
})

-- Haswell (HD 4600 / i915) display workarounds.
-- Symptom: under Hyprland the top half of the eDP panel stops painting
-- (black/stale band), while MangoWM on the same machine is fine. Both the
-- hardware cursor plane and direct scanout are known to corrupt older
-- Intel display pipelines: the cursor plane fails to lift, and scanout
-- keeps presenting a stale buffer over part of the panel. A software
-- cursor and no direct scanout cost a little CPU/power but composite
-- correctly. Drop these two lines on a newer GPU.
hl.config({
	cursor = {
		no_hardware_cursors = true,
	},
	render = {
		direct_scanout = 0, -- 0 = off · 1 = fullscreen only · 2 = always
	},
})
