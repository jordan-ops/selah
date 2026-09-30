---------------------
---- MY PROGRAMS ----
---------------------

-- Set programs that you use.
-- Returned as a table so binds.lua (and anything else) can pick them up:
--   local programs = require("programs")
--   local terminal = programs.terminal
return {
    terminal    = "foot",
    fileManager = "nautilus",
    -- quickshell's own launcher via IPC (hyprlauncher not installed —
    -- quickshell handles menus now; Super+Space hits the same launcher)
    menu        = "qs ipc call launcher toggle",
    browser     = "chromium",
}
