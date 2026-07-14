-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Disable LazyVim's format-on-save; formatting is manual (<leader>uf) so a
-- formatter resolved on the host cannot silently reformat code that a
-- devcontainer owns.
vim.g.autoformat = false
