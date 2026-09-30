---------------------
---- MY PROGRAMS ----
---------------------

-- Set programs that you use.
-- Returned as a table so binds.lua (and anything else) can pick them up:
--   local programs = require("programs")
--   local terminal = programs.terminal
--
-- terminal / fileManager / browser route through default-apps.sh so the
-- Settings ▸ Default apps rows govern what these binds open: the script
-- resolves the pick at LAUNCH time (xdg-mime default, or settings.json for
-- the terminal), so changing a default needs no config reload. Until
-- something is picked it falls back to foot / nautilus / chromium — the
-- same apps as always.
local src = nil
if type(debug) == "table" and debug.getinfo then
    src = debug.getinfo(1, "S").source
end
local root = (src and src:sub(1, 1) == "@")
    and src:sub(2):match("^(.*)/config/hypr/[^/]+$") or nil
if not root then
    -- debug info stripped, or config copied out of the repo: the
    -- canonical clone location is the documented fallback
    root = ((os and os.getenv and os.getenv("HOME")) or "") .. "/.dotfiles"
end
local launch = "sh '" .. root .. "/config/quickshell/scripts/default-apps.sh' launch"

return {
    terminal    = launch .. " terminal",
    fileManager = launch .. " filemanager",
    -- quickshell's own launcher via IPC (hyprlauncher not installed —
    -- quickshell handles menus now; Super+Space hits the same launcher)
    menu        = "qs ipc call launcher toggle",
    browser     = launch .. " browser",
}
