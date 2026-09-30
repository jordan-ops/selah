-- AstroUI provides the basis for configuring the AstroNvim User Interface
--
-- COLOUR COORDINATION: `colorscheme = "quickshell"` points AstroNvim at
-- ~/.config/nvim/colors/quickshell.lua, which global-theme.py regenerates
-- from the active theme's colors.toml on every switch (same file LazyVim
-- used, and the same pipeline the rest of the desktop runs through), so
-- nvim always matches the shell's current theme. `highlights.quickshell`
-- is applied on top of that file — it exists only as the override slot for
-- AstroNvim-specific groups that should track the shell rather than the
-- (unused) astrotheme palette. The per-mode statusline colours are handled
-- separately in lua/lualine/themes/quickshell.lua.
---@type LazySpec
return {
  "AstroNvim/astroui",
  ---@type AstroUIOpts
  opts = {
    -- change colorscheme
    colorscheme = "quickshell",
    -- AstroUI allows you to easily modify highlight groups for any colorscheme
    highlights = {
      init = { -- this table overrides highlights in all themes
        -- Normal = { bg = "#000000" },
      },
      -- Applied on top of the generated colorscheme on every ColorScheme
      -- event.
      --
      -- GitSigns*: heirline evaluates setup_colors() once, at BufEnter, which
      -- can beat gitsigns' own setup — so at that moment GitSignsAdd is still
      -- undefined and AstroNvim takes its astrotheme fallback (green/orange/
      -- red), exactly the off-palette colours that used to show in the diff
      -- counts. Defining them here, at colorscheme time, is the only order-
      -- independent fix. Added/Changed/Removed are Neovim built-ins that
      -- gitsigns links to, and NvimEnvironmentName only astrotheme defines.
      -- Everything points at the theme's own groups, so a monochrome theme
      -- gets greys and a colour theme gets real diff colours.
      quickshell = {
        GitSignsAdd = { link = "DiffAdd" },
        GitSignsChange = { link = "DiffChange" },
        GitSignsDelete = { link = "DiffDelete" },
        Added = { link = "DiffAdd" },
        Changed = { link = "DiffChange" },
        Removed = { link = "DiffDelete" },
        NvimEnvironmentName = { link = "String" },
      },
    },
    -- Icons can be configured throughout the interface
    icons = {
      -- configure the loading of the lsp in the status line
      LSPLoading1 = "⠋",
      LSPLoading2 = "⠙",
      LSPLoading3 = "⠹",
      LSPLoading4 = "⠸",
      LSPLoading5 = "⠼",
      LSPLoading6 = "⠴",
      LSPLoading7 = "⠦",
      LSPLoading8 = "⠧",
      LSPLoading9 = "⠇",
      LSPLoading10 = "⠏",
    },
  },
}
