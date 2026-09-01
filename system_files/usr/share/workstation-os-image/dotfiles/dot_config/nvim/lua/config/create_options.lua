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
-- supports it natively, and herdr forwards pane OSC 52 writes to the attached
-- client with no configuration of its own. Inert on the host.
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

-- Dev Containers usually default to plain /bin/sh; prefer bash for `:terminal`
-- and shell commands. bash is POSIX-compatible, so plugins that shell out are
-- unaffected. fish is not POSIX, so it is never set as 'shell'; the <C-t>
-- terminal mapping opens fish only when the container actually ships it.
if os.getenv("NVIM_IN_CONTAINER") and vim.fn.executable("bash") == 1 then
  vim.o.shell = vim.fn.exepath("bash")
end

-- Reload a file the moment it changes on disk. A coding agent editing the
-- project while a buffer is open is the normal case here, not the exception.
vim.o.autoread = true

-- Write on leaving insert or after a change. Formatting deliberately does NOT
-- run here: vim.g.autoformat above stays false, so an agent reading the file
-- always sees current text without a host-resolved formatter rewriting code a
-- devcontainer owns.
vim.api.nvim_create_autocmd({ "TextChanged", "InsertLeave" }, {
  group = vim.api.nvim_create_augroup("user_autosave", { clear = true }),
  callback = function()
    if vim.bo.modified and vim.bo.buftype == "" and vim.api.nvim_buf_get_name(0) ~= "" then
      vim.cmd("silent! write")
    end
  end,
})

-- Auto-save covers the crash-recovery case swap files exist for, and a stale
-- .swp after a herdr server restart is a prompt on every reopen.
vim.opt.swapfile = false

-- Absolute line numbers: the relative pair is for counted motions, which
-- hardtime already discourages.
vim.opt.relativenumber = false

-- Case-insensitive search even when the pattern has uppercase. LazyVim ships
-- smartcase, which silently flips to case-sensitive the moment you type one.
vim.opt.ignorecase = true
vim.opt.smartcase = false

-- Wrap at word boundaries rather than scrolling horizontally.
vim.opt.wrap = true
vim.opt.linebreak = true

-- `gf` over a TypeScript "@/" import. Harmless where no such alias exists.
vim.opt.isfname:append("@-@")
vim.opt.path:append("src/**")
vim.opt.suffixesadd:append(".ts,.tsx,.js,.jsx,.json")
vim.opt.includeexpr = "substitute(v:fname,'^@/','src/','g')"

-- SQLite files are binary: mark them so previewers skip them instead of dumping
-- raw bytes. Open them with DBUI (see lua/plugins/db.lua) instead.
vim.filetype.add({
  extension = {
    db = "sqlite",
    sqlite = "sqlite",
    sqlite3 = "sqlite",
  },
})
