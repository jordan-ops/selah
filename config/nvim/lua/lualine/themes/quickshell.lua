-- Statusline MODE colours for AstroNvim, derived from whatever colorscheme is
-- actually loaded.
--
-- AstroNvim builds its statusline palette in `setup_colors()` (astronvim/
-- plugins/_astroui_status.lua). For the per-mode block it does:
--
--     resolve_lualine(get_hlgroup("HeirlineNormal", { bg = nil }).bg,
--                     "normal", color.blue)
--
-- `Heirline*` is defined only by astrotheme, which is NOT the colorscheme
-- here — colors/quickshell.lua is regenerated from the active shell theme by
-- global-theme.py. With no `Heirline*` group the expression is nil, so
-- `astroui.status.hl.lualine_mode()` runs:
--
--     pcall(require, "lualine.themes." .. vim.g.colors_name)
--
-- i.e. it looks for THIS file (colors_name == "quickshell"). Sourcing the
-- colours from the loaded colorscheme's own ANSI palette keeps the mode block
-- in step with the desktop theme, instead of silently dropping back to
-- astrotheme's hardcoded one-dark blue/green/purple.
--
-- Read lazily-safe: every value is nil if the colorscheme has not run yet, and
-- a nil `a.bg` makes lualine_mode return AstroNvim's fallback — so a stray
-- require order can only lose the accent, never break the statusline.

local function hl(name)
  -- link = false: resolve the group itself, not whatever it links to, so a
  -- colorscheme that leaves these as links still reports its own intent
  local ok, res = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
  return ok and res or {}
end

local function hex(n)
  return type(n) == "number" and string.format("#%06x", n) or nil
end

-- text drawn on the block = the statusline background (AstroNvim's own
-- mode_fg picks the same value), inactive sits on the base background
local on_block = hex(hl("StatusLine").bg)
local base = hex(hl("Normal").bg)

-- the shell theme's 16-colour ANSI palette — the same table
-- global-theme.py writes into colors/quickshell.lua on every switch
local function ansi(i)
  local c = vim.g["terminal_color_" .. i]
  return type(c) == "string" and c or nil
end

local function mode(bg)
  -- bright variants (9-14) rather than the normal-intensity ones: they are
  -- light enough for the dark mode_fg AstroNvim puts on top of them
  return {
    a = { fg = on_block, bg = bg },
    b = { fg = bg, bg = base },
    c = { fg = on_block, bg = base },
  }
end

return {
  normal = mode(ansi(12)), -- bright blue
  insert = mode(ansi(10)), -- bright green
  visual = mode(ansi(13)), -- bright magenta
  replace = mode(ansi(9)), -- bright red
  command = mode(ansi(11)), -- bright yellow
  terminal = mode(ansi(14)), -- bright cyan
  inactive = mode(ansi(8)), -- bright black / the theme's grey
}
