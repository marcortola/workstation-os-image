-- Vim-motion training aids. Both are learning scaffolding, not editor features:
-- remove this file once the habits stick. They apply to Neovim only; the
-- JetBrains IDEs are Vim-agnostic and have nothing equivalent.
return {
  -- Coaches better motions. Two independent mechanisms, deliberately set to
  -- different strengths:
  --
  --   restricted_keys (hjkl, +, gj, gk) run in HINT mode — never blocked, you
  --   just get told what the shorter form was ("Use ct( instead of dt(i", "Use -
  --   instead of k^"). Change restriction_mode to "block" to have the 4th
  --   consecutive press inside 1s swallowed instead.
  --
  --   disabled_keys (the arrow keys, in normal and insert) are hard-blocked and
  --   are NOT governed by restriction_mode. That is intentional: arrows are the
  --   one habit worth killing outright. Re-enable them by adding
  --   disabled_keys = { ["<Up>"] = false, ["<Down>"] = false, ["<Left>"] = false,
  --   ["<Right>"] = false } to opts.
  --
  -- `:Hardtime report` ranks the hints you trigger most, which is the actual
  -- point — it turns vague "I type badly" into a list of five habits.
  {
    "m4xshen/hardtime.nvim",
    dependencies = { "MunifTanjim/nui.nvim" },
    event = "VeryLazy",
    opts = {
      restriction_mode = "hint", -- "block" to actually enforce
      disable_mouse = false, -- the mouse is not the habit being trained
    },
    keys = {
      { "<leader>uH", "<cmd>Hardtime toggle<cr>", desc = "Toggle Hardtime" },
      { "<leader>uR", "<cmd>Hardtime report<cr>", desc = "Hardtime Report" },
    },
  },

  -- Shows which motion reaches which point on the current line as virtual text
  -- (^ w b e W B E $ %, gutter gg/G/{/}). Off by default because it is noisy on
  -- every line; toggle it on for a stretch of deliberate practice.
  {
    "tris203/precognition.nvim",
    event = "VeryLazy",
    opts = {
      startVisible = false,
    },
    keys = {
      -- Not <leader>up: LazyVim already maps that to the mini.pairs toggle
      -- (lua/lazyvim/util/mini.lua).
      { "<leader>uv", "<cmd>Precognition toggle<cr>", desc = "Toggle Precognition" },
      { "<leader>uV", "<cmd>Precognition peek<cr>", desc = "Precognition Peek" },
    },
  },
}
