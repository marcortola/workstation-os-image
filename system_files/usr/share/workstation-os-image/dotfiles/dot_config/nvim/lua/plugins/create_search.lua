-- grug-far ships with LazyVim but binds nothing useful by default; undotree is
-- the one addition, for the times a linear undo history is not enough.
return {
  {
    "MagicDuck/grug-far.nvim",
    cmd = "GrugFar",
    keys = {
      {
        "<leader>sr",
        function()
          require("grug-far").open({ prefills = { paths = vim.fn.expand("%") } })
        end,
        desc = "Search & Replace (current file)",
      },
      {
        "<leader>sR",
        function()
          require("grug-far").open()
        end,
        desc = "Search & Replace (root)",
      },
      {
        "<leader>sr",
        function()
          require("grug-far").with_visual_selection({ prefills = { paths = vim.fn.expand("%") } })
        end,
        mode = "v",
        desc = "Search & Replace (selection)",
      },
    },
    opts = {},
  },
  {
    "mbbill/undotree",
    keys = {
      { "<leader>uu", "<cmd>UndotreeToggle<cr>", desc = "Undotree (undo history)" },
    },
    init = function()
      vim.g.undotree_WindowLayout = 4
      vim.g.undotree_SetFocusWhenToggle = 1
    end,
  },
}
