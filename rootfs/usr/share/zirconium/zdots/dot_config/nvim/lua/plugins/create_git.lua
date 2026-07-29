-- Git parity beyond LazyVim's gitsigns + snacks(lazygit): diffview for visual
-- side-by-side diff / file history / 3-way merge, and git-conflict for inline
-- conflict resolution. Keymaps use the free <leader>gv/<leader>gV slots so they
-- do not clash with snacks/gitsigns git bindings.
return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
    keys = {
      { "<leader>gv", "<cmd>DiffviewOpen<cr>", desc = "Diffview (open)" },
      { "<leader>gV", "<cmd>DiffviewFileHistory %<cr>", desc = "Diffview file history" },
    },
    opts = {},
  },
  {
    "akinsho/git-conflict.nvim",
    version = "*",
    -- Host only: git-conflict runs git eagerly on load and hangs inside a Dev
    -- Container (`dev nvim`); commits/merges are done host-side anyway, and
    -- diffview handles in-container merge viewing.
    cond = function() return not vim.env.NVIM_IN_CONTAINER end,
    event = "VeryLazy",
    opts = {},
  },
}
