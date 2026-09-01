-- Group labels for the prefixes this config adds, and hides for LazyVim
-- defaults that are mapped but never used here. Hidden entries stay bound --
-- this only trims the panel.
return {
  "folke/which-key.nvim",
  opts = {
    spec = {
      { "<leader>d", group = "database" },
      { "<leader>D", group = "docker" },

      { "<leader>S", desc = "Search Global (Grep)" },
      { "<leader>uu", desc = "Undotree (undo history)" },
      { "<leader>H", desc = "Home (Dashboard)" },

      -- Git defaults superseded by Diffview and the <leader>gs stage toggle
      { "<leader>gB", hidden = true },
      { "<leader>gD", hidden = true },
      { "<leader>gf", hidden = true },
      { "<leader>gl", hidden = true },
      { "<leader>gL", hidden = true },
      { "<leader>gS", hidden = true },
      { "<leader>gY", hidden = true },

      -- Buffer and file entries covered by the pickers
      { "<leader>bb", hidden = true },
      { "<leader>bP", hidden = true },
      { "<leader>bl", hidden = true },
      { "<leader>fb", hidden = true },
      { "<leader>fe", hidden = true },
      { "<leader>fE", hidden = true },

      -- Tabs: this workflow uses buffers and herdr tabs, not vim tabpages
      { "<leader><Tab>", hidden = true },
    },
  },
}
