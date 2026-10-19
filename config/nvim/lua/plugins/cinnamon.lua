---@type LazySpec
return {
  "declancm/cinnamon.nvim",
  version = "*", -- use latest release
  opts = {
    keymaps = {
      -- 'basic': <C-U>/<C-D>, <C-B>/<C-F>, { }, n/N/*/#, <C-O>/<C-I>
      basic = true,
      -- 'extra': gg/G, 0/^/$, zz/zt/zb, j/k/h/l (+ arrows and counts)
      extra = true,
    },
    options = {
      -- "cursor": animate the cursor AND window scroll
      -- "window": only animate the window when the cursor leaves the view
      mode = "cursor",

      -- ms between each movement step. Lower = faster, choppier.
      delay = 5,

      max_delta = {
        -- Skip the animation entirely for jumps longer than this many lines.
        -- `false` = never skip, but `time` below still caps total duration.
        line = false,
        column = false,
        -- Hard cap on how long any movement may take (scales delay + step size)
        time = 400,
      },

      step_size = {
        -- Lines moved per step. Raise for a snappier feel, lower for silkier.
        vertical = 1,
        -- Columns moved per step
        horizontal = 2,
      },
    },
  },
}
