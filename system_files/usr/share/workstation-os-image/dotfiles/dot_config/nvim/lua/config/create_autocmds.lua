-- Autocmds are automatically loaded on the VeryLazy event
-- Default autocmds that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/autocmds.lua
--
-- Add any additional autocmds here
-- with `vim.api.nvim_create_autocmd`
--
-- Or remove existing autocmds by their group name (which is prefixed with `lazyvim_` for the defaults)
-- e.g. vim.api.nvim_del_augroup_by_name("lazyvim_wrap_spell")

-- Snacks reads the actual window width rather than the configured one when a
-- split layout is resized, so the explorer goes full-width after a terminal
-- resize -- including herdr's `prefix+plus` pane equalize. Restore the
-- configured width once Snacks has finished its own resize handling.
vim.api.nvim_create_autocmd("VimResized", {
  group = vim.api.nvim_create_augroup("user_snacks_explorer_resize", { clear = true }),
  callback = function()
    vim.defer_fn(function()
      local ok, pickers = pcall(function()
        return Snacks.picker.get({ source = "explorer" })
      end)
      if not ok or not pickers then
        return
      end
      for _, p in ipairs(pickers) do
        local width = p.resolved_layout and p.resolved_layout.layout and p.resolved_layout.layout.width or 40
        if p.layout and p.layout.root and p.layout.root:valid() then
          local win = p.layout.root.win
          if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_width(win) ~= width then
            vim.api.nvim_win_set_width(win, width)
            p.layout:update()
          end
        end
      end
    end, 10)
  end,
})
