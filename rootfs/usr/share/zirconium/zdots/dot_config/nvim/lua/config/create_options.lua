-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- Disable LazyVim's format-on-save; formatting is manual (<leader>uf) so a
-- formatter resolved on the host cannot silently reformat code that a
-- devcontainer owns.
vim.g.autoformat = false

-- LSP selection for LazyVim language extras (must be set before lazy loads).
vim.g.lazyvim_python_lsp = "basedpyright" -- over the stock pyright
vim.g.lazyvim_php_lsp = "intelephense" -- premium; phpactor added separately as RPC-only

-- Inside a Dev Container (`dev nvim`) there is no Wayland/X clipboard tool, so
-- route the system clipboard through OSC 52 (a terminal escape sequence). foot
-- supports it natively; tmux/workmux needs `set -g set-clipboard on` and
-- `allow-passthrough on` (shipped in the tmux config). Inert on the host.
if os.getenv("NVIM_IN_CONTAINER") then
  local ok, osc52 = pcall(require, "vim.ui.clipboard.osc52")
  if ok then
    vim.g.clipboard = {
      name = "OSC52",
      copy = { ["+"] = osc52.copy("+"), ["*"] = osc52.copy("*") },
      paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
    }
  end
end
