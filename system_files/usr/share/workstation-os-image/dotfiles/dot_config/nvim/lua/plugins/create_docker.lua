-- lazydocker is already installed, has a repo-owned config and a niri bind
-- (Mod+Shift+D), but nothing reached it without leaving the editor.
return {
  "folke/snacks.nvim",
  keys = {
    {
      "<leader>DD",
      function()
        Snacks.terminal("lazydocker", { cwd = vim.fn.getcwd() })
      end,
      desc = "Lazydocker",
    },
  },
}
