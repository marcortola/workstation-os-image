-- Keymaps are automatically loaded on the VeryLazy event
-- Default LazyVim keymaps: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
--
-- This file was once deliberately empty so that every binding also existed in
-- the JetBrains IDEs through ~/.ideavimrc. That rule is retired twice over:
-- most of what is worth binding drives Snacks pickers, Diffview and the herdr
-- pane navigation, none of which has a JetBrains equivalent, and the IDEs no
-- longer emulate Vim at all -- they keep their own keymap as the alternative to
-- this flow. Bind whatever is useful here; nothing has to agree with them.
--
-- Stock LazyVim keys worth remembering before adding anything here:
--   move line/selection      <A-j> / <A-k>
--   duplicate line           yyp   (or :t. for a count)
--   delete line              dd
--   expand/shrink selection  <C-Space> / <BS>   (flash.nvim treesitter), or S
--   change case              vim-abolish coercions, see lua/plugins/abolish.lua
--   terminal                 <C-/>, <leader>ft (root dir), <leader>fT (cwd)
--   jump back / forward      <C-o> / <C-i>
--   rename symbol            <leader>cr
--
-- Note on <C-Space>: it reaches Neovim unintercepted. herdr takes Ctrl+g as its
-- prefix and fcitx5 was moved off Ctrl+Space (see
-- workstation-cycle-keyboard-layout). S (Flash Treesitter) remains the faster
-- alternative: it labels every enclosing node at once instead of stepping
-- outward one at a time.
local Path = require("util.path")

vim.keymap.set("i", "jk", "<Escape>")

-- Navigate cmdline completion popup with <C-j>/<C-k> (mirrors blink.cmp)
vim.keymap.set("c", "<C-j>", "<C-n>", { silent = false })
vim.keymap.set("c", "<C-k>", "<C-p>", { silent = false })

-- Buffer search with "f" (flash's char keys are adjusted in plugins/flash.lua)
vim.keymap.set("n", "f", "/", { desc = "Search in buffer" })

local ENTRY_POINT_FILES = { index = true, init = true, __init__ = true, mod = true }

-- Entry points and Go files are referenced by their directory, not by their own name.
local function reference_names(path)
  local stem = vim.fn.fnamemodify(path, ":t:r")
  local dir = vim.fn.fnamemodify(path, ":h:t")
  if dir == "" or dir == "." or dir == stem then
    return { stem }
  elseif ENTRY_POINT_FILES[stem] then
    return { dir }
  elseif path:match("%.go$") then
    return { stem, dir }
  end
  return { stem }
end

local function selected_picker_file()
  local picker = (Snacks.picker.get() or {})[1]
  if not picker then
    return nil
  end
  local selected = picker:selected({ fallback = true })
  return selected and selected[1] and selected[1].file
end

-- Which files use this one: the Snacks explorer selection, or the current buffer
vim.keymap.set("n", "<leader>fi", function()
  local file = selected_picker_file() or vim.api.nvim_buf_get_name(0)
  if file == "" or file:find("://", 1, true) then
    vim.notify("No file to look up", vim.log.levels.WARN)
    return
  end

  local names = vim.tbl_map(function(name)
    return vim.fn.escape(name, "\\^$.*+?()[]{}|")
  end, reference_names(file))

  local root = LazyVim.root()
  Snacks.picker.grep({
    cwd = root,
    search = "\\b(" .. table.concat(names, "|") .. ")\\b",
    exclude = file:find(root, 1, true) == 1 and { file:sub(#root + 2) } or nil,
    title = "Used by · " .. vim.fn.fnamemodify(file, ":t"),
  })
end, { desc = "Find file usages" })

-- Refresh buffer from disk
vim.keymap.set("n", "<leader>br", "<cmd>e!<cr>", { desc = "Refresh buffer" })

-- Yank current buffer's path (relative with @/ alias, or absolute)
vim.keymap.set("n", "<leader>fy", function()
  local file = vim.fn.expand("%")
  if file == "" then
    vim.notify("No file open", vim.log.levels.INFO)
    return
  end
  local path = Path.relative(file)
  vim.fn.setreg("+", path)
  vim.notify("Copied: " .. path, vim.log.levels.INFO)
end, { desc = "Yank file path (relative)" })

vim.keymap.set("n", "<leader>fY", function()
  local file = vim.fn.expand("%")
  if file == "" then
    vim.notify("No file open", vim.log.levels.INFO)
    return
  end
  local path = Path.absolute(file)
  vim.fn.setreg("+", path)
  vim.notify("Copied: " .. path, vim.log.levels.INFO)
end, { desc = "Yank file path (absolute)" })

-- Delete without overwriting register (use "d to cut)
vim.keymap.set("n", "d", '"_d', { desc = "Delete without register" })
vim.keymap.set("n", "D", '"_D', { desc = "Delete to end without register" })
vim.keymap.set("x", "d", '"_d', { desc = "Delete without register" })
vim.keymap.set("x", "p", '"_dP', { desc = "Paste without overwriting register" })

-- Toggle stage/unstage of the current file. Mirrors "gs" in the Snacks explorer
-- and "-" in the Diffview file panel (plugins/git.lua maps <leader>gs there too).
vim.keymap.set("n", "<leader>gs", function()
  local file = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype ~= "" or file == "" or file:find("://", 1, true) then
    vim.notify("No file to stage in this buffer", vim.log.levels.WARN)
    return
  end

  local name = vim.fn.fnamemodify(file, ":t")
  local dir = vim.fn.fnamemodify(file, ":h")
  local status = vim.fn.systemlist({ "git", "-C", dir, "status", "--porcelain", "--", file })[1]
  if vim.v.shell_error ~= 0 then
    vim.notify("Not a git repository", vim.log.levels.WARN)
    return
  end
  if not status then
    vim.notify("No changes: " .. name, vim.log.levels.INFO)
    return
  end

  -- Porcelain is "XY path": a blank worktree column means nothing is left unstaged
  local staged = status:sub(2, 2) == " "
  local cmd = staged and { "git", "-C", dir, "restore", "--staged", "--", file }
    or { "git", "-C", dir, "add", "--", file }
  vim.fn.system(cmd)
  if vim.v.shell_error ~= 0 then
    vim.notify("git failed on " .. name, vim.log.levels.ERROR)
    return
  end

  vim.notify((staged and "Unstaged: " or "Staged: ") .. name, vim.log.levels.INFO)
end, { desc = "Stage/unstage file" })

-- Global grep (always works, any context)
vim.keymap.set("n", "<leader>S", function()
  Snacks.picker.grep()
end, { desc = "Search Global (Grep)" })

-- Splits
vim.keymap.set("n", "<leader>sv", "<cmd>vsplit<cr>", { desc = "Split vertical" })
vim.keymap.set("n", "<leader>sx", "<cmd>close<cr>", { desc = "Close split" })

-- Throwaway scratch for secrets: floating buffer wiped on close. Snacks' <leader>.
-- persists to ~/.local/share/nvim/scratch, which is the wrong place for a token.
vim.keymap.set("n", "<leader>n", function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].filetype = "markdown"
  -- Scrub the shada-persisted registers on close so a yanked secret leaves no
  -- trace; "+ (system clipboard) is kept so the credential can still be pasted out.
  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      for _, reg in ipairs({ "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "-", "/" }) do
        pcall(vim.fn.setreg, reg, "")
      end
    end,
  })
  local win = Snacks.win({
    buf = buf,
    enter = true,
    width = 0.6,
    height = 0.6,
    border = "rounded",
    title = " Scratch (secrets, not saved) ",
    title_pos = "center",
  })
  vim.keymap.set("n", "<Esc>", function()
    win:close()
  end, { buffer = buf })
  vim.keymap.set("i", "<C-c>", "<Esc>", { buffer = buf })
  vim.keymap.set("n", "<C-c>", function()
    win:close()
  end, { buffer = buf })
  -- Open focused and ready to type; the float can need a tick to take focus.
  vim.schedule(function()
    if win.win and vim.api.nvim_win_is_valid(win.win) then
      vim.api.nvim_set_current_win(win.win)
      vim.cmd("startinsert")
    end
  end)
end, { desc = "Scratch volatile (secrets, not saved)" })

-- Close every buffer and return to the dashboard
vim.keymap.set("n", "<leader>H", function()
  for _, buf in ipairs(vim.fn.getbufinfo({ buflisted = 1 })) do
    pcall(vim.api.nvim_buf_delete, buf.bufnr, { force = false })
  end
  Snacks.dashboard.open()
end, { desc = "Home (Dashboard)" })
