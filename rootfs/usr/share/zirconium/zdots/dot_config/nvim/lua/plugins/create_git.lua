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
    event = "VeryLazy",
    opts = {},
  },
}
