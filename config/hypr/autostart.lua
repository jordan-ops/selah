-------------------
---- AUTOSTART ----
-------------------

-- See https://wiki.hypr.land/Configuring/Basics/Autostart/

-- Autostart necessary processes (like notifications daemons, status bars, etc.)
-- Or execute your favorite apps at launch like this:
--
hl.on("hyprland.start", function()
	hl.exec_cmd("qs")
	-- MEGAsync: keeps ~/MEGA backups syncing and gives the apps tray
	-- a StatusNotifier icon from the very first login.
	hl.exec_cmd("megasync &")
	--	hl.exec_cmd("nm-applet")
	-- hl.exec_cmd("waybar & hyprpaper & firefox")
end)
