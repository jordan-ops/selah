---------------------
---- KEYBINDINGS ----
---------------------

-- Programs live in programs.lua so every module shares one definition.
local programs = require("programs")
local terminal    = programs.terminal
local fileManager = programs.fileManager
local menu        = programs.menu
local browser     = programs.browser

local mainMod = "SUPER" -- Sets "Windows" key as main modifier

-- Example binds, see https://wiki.hypr.land/Configuring/Basics/Binds/ for more
hl.bind(mainMod .. " + RETURN", hl.dsp.exec_cmd(terminal))
local closeWindowBind = hl.bind(mainMod .. " + W", hl.dsp.window.close())
-- closeWindowBind:set_enabled(false)
hl.bind(mainMod .. " + M", hl.dsp.exec_cmd("command -v hyprshutdown >/dev/null 2>&1 && hyprshutdown || hyprctl dispatch 'hl.dsp.exit()'"))
hl.bind(mainMod .. " + E", hl.dsp.exec_cmd(fileManager))
-- Float toggle + center: window rules only apply at map time, so the
-- center-floats rule can't catch a window floated mid-session.
hl.bind(mainMod .. " + V", hl.dsp.exec_cmd(
    "hyprctl dispatch 'hl.dsp.window.float({ action = \"toggle\" })'; "
    .. "hyprctl dispatch 'hl.dsp.window.center()'"))

-- Aspect-fit fullscreen: scales the window to fit the monitor keeping
-- its exact shape, centered, never edge-to-edge (gaps + bar visible).
-- Press again to restore / re-tile. Escape hatches below.
hl.bind(mainMod .. " + F", hl.dsp.exec_cmd("bash ~/.local/bin/aspect-fit.sh"))
hl.bind(mainMod .. " + SHIFT + F", hl.dsp.window.fullscreen({ action = "toggle" }))
hl.bind(mainMod .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(mainMod .. " + R", hl.dsp.exec_cmd(menu))
hl.bind(mainMod .. " + P", hl.dsp.window.pseudo())
hl.bind(mainMod .. " + J", hl.dsp.layout("togglesplit"))    -- dwindle only

hl.bind(mainMod .. " + B", hl.dsp.exec_cmd(browser))
-- Move focus with mainMod + arrow keys
hl.bind(mainMod .. " + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(mainMod .. " + right", hl.dsp.focus({ direction = "right" }))
hl.bind(mainMod .. " + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(mainMod .. " + down",  hl.dsp.focus({ direction = "down" }))

-- Switch workspaces with mainMod + [0-9]
-- Move active window to a workspace with mainMod + SHIFT + [0-9]
for i = 1, 10 do
    local key = i % 10 -- 10 maps to key 0
    hl.bind(mainMod .. " + " .. key,             hl.dsp.focus({ workspace = i}))
    hl.bind(mainMod .. " + SHIFT + " .. key,     hl.dsp.window.move({ workspace = i }))
end

-- Example special workspace (scratchpad)
hl.bind(mainMod .. " + S",         hl.dsp.workspace.toggle_special("magic"))
hl.bind(mainMod .. " + SHIFT + S", hl.dsp.window.move({ workspace = "special:magic" }))

-- Scroll through existing workspaces with mainMod + scroll
hl.bind(mainMod .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(mainMod .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))

-- Move/resize windows with mainMod + LMB/RMB and dragging
hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Laptop multimedia keys for volume and LCD brightness
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"),      { locked = true, repeating = true })
hl.bind("XF86AudioMute",        hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"),     { locked = true, repeating = true })
hl.bind("XF86AudioMicMute",     hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"),   { locked = true, repeating = true })
hl.bind("XF86MonBrightnessUp",  hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%+"),                  { locked = true, repeating = true })
hl.bind("XF86MonBrightnessDown",hl.dsp.exec_cmd("brightnessctl -e4 -n2 set 5%-"),                  { locked = true, repeating = true })

-- Requires playerctl
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"),       { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"),   { locked = true })


--------------------------
---- QUICKSHELL BINDS ----
--------------------------
-- All of these talk to the running quickshell instance via `qs ipc call`.
-- Each target/function pair lives in an IpcHandler inside the matching
-- services/*.qml file — `qs ipc show` lists everything currently exposed.

hl.bind(mainMod .. " + space",                 hl.dsp.exec_cmd("qs ipc call launcher toggle"))
hl.bind(mainMod .. " + N",                     hl.dsp.exec_cmd("qs ipc call controlcenter toggle"))
hl.bind(mainMod .. " + Escape",                hl.dsp.exec_cmd("qs ipc call powermenu toggle"))
hl.bind(mainMod .. " + I",                     hl.dsp.exec_cmd("qs ipc call clockcard toggle"))
hl.bind(mainMod .. " + CTRL + space",          hl.dsp.exec_cmd("qs ipc call wallpaper toggle"))   -- wallpaper picker (quickshell strip)
hl.bind(mainMod .. " + CTRL + SHIFT + space",  hl.dsp.exec_cmd("qs ipc call theme toggle"))
hl.bind(mainMod .. " + ALT + W",               hl.dsp.exec_cmd("qs ipc call aether toggle"))      -- aether palette carousel (extract from wallpaper)
hl.bind(mainMod .. " + SHIFT + N",             hl.dsp.exec_cmd("qs ipc call nightlight toggle"))
hl.bind(mainMod .. " + SHIFT + V",             hl.dsp.exec_cmd("qs ipc call clipboard toggle"))   -- clipboard history
hl.bind(mainMod .. " + ALT + U",               hl.dsp.exec_cmd("qs ipc call updates toggle"))
hl.bind(mainMod .. " + semicolon",             hl.dsp.exec_cmd("qs ipc call settingsapp toggle"))  -- settings app

-- Full-screen screenshot to ~/Pictures/Screenshots + clipboard
hl.bind("Print", hl.dsp.exec_cmd("bash ~/.local/bin/screenshot.sh"))

-- Lock screen — quickshell's own session lock (ext-session-lock + PAM),
-- no hyprlock. First-time setup: ~/.local/bin/qs-lock-pam
hl.bind(mainMod .. " + L", hl.dsp.exec_cmd("qs ipc call lock lock"))
hl.bind("SUPER + SHIFT + X", hl.dsp.exec_cmd("kitty"))
hl.bind("SUPER + SHIFT + R", hl.dsp.exec_cmd("pkill qs && sleep 3s && qs & disown"))  -- premitive quickshell reload
