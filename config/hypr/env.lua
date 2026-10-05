-------------------------------
---- ENVIRONMENT VARIABLES ----
-------------------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Environment-variables/

hl.env("XCURSOR_SIZE", "20")
hl.env("HYPRCURSOR_SIZE", "20")

-- Qt apps (qBittorrent, megasync, android-file-transfer, ...) load the
-- qt5ct/qt6ct platform themes: the colon list lets each Qt major pick
-- the plugin it knows. Both are set up to follow the GTK side —
-- switch-theme.sh regenerates colors/selah.conf from colors.toml, plus
-- the Yaru-sage-dark icon theme and the JetBrainsMono font.
-- https://wiki.archlinux.org/title/Qt
hl.env("QT_QPA_PLATFORMTHEME", "qt5ct:qt6ct")

hl.env("XDG_CURRENT_DESKTOP", "Hyprland", true)
hl.env("XDG_SESSION_TYPE", "wayland", true)
hl.env("XDG_SESSION_DESKTOP", "Hyprland", true)

hl.on("hyprland.start", function()
	hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP")
end)
-----------------------
----- PERMISSIONS -----
-----------------------

-- See https://wiki.hypr.land/Configuring/Advanced-and-Cool/Permissions/
-- Please note permission changes here require a Hyprland restart and are not applied on-the-fly
-- for security reasons

-- hl.config({
--   ecosystem = {
--     enforce_permissions = true,
--   },
-- })

-- hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
-- hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
-- hl.permission("/usr/(bin|local/bin)/hyprpm", "plugin", "allow")
