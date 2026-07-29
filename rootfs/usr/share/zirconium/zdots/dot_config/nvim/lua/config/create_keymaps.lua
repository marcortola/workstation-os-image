-- Keymaps are automatically loaded on the VeryLazy event
-- Default LazyVim keymaps: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/keymaps.lua
--
-- JetBrains-parity editing keys. The workstation terminal (foot) speaks the
-- kitty keyboard protocol, so Neovim can tell Alt+Shift+Arrow / Ctrl+Shift+key
-- apart from the plain keys. Where a faithful JetBrains key would clobber an
-- essential Vim key, the binding is shifted and the swap is called out inline so
-- you can flip it back if you prefer the exact key.
local map = vim.keymap.set

-- Move line / selection up & down  (JetBrains: Alt+Shift+Up/Down)
-- No Vim conflict. LazyVim's <A-j>/<A-k> keep working as a plain-Alt fallback.
map("n", "<A-S-Down>", "<cmd>execute 'move .+' . v:count1<cr>==", { desc = "Move line down" })
map("n", "<A-S-Up>", "<cmd>execute 'move .-' . (v:count1 + 1)<cr>==", { desc = "Move line up" })
map("i", "<A-S-Down>", "<esc><cmd>m .+1<cr>==gi", { desc = "Move line down" })
map("i", "<A-S-Up>", "<esc><cmd>m .-2<cr>==gi", { desc = "Move line up" })
map("v", "<A-S-Down>", ":m '>+1<cr>gv=gv", { desc = "Move selection down" })
map("v", "<A-S-Up>", ":m '<-2<cr>gv=gv", { desc = "Move selection up" })

-- Duplicate line / selection  (JetBrains: Ctrl+D)
-- Bound to Ctrl+Shift+D so Vim's Ctrl+D (half-page down) survives; change the
-- "<C-S-d>" below to "<C-d>" if you want the exact JetBrains key.
map("n", "<C-S-d>", "<cmd>t.<cr>", { desc = "Duplicate line" })
map("v", "<C-S-d>", ":t'><cr>gv", { desc = "Duplicate selection" })
map("i", "<C-S-d>", "<esc><cmd>t.<cr>gi", { desc = "Duplicate line" })

-- Delete line  (JetBrains: Ctrl+Y)
-- Overrides Vim's little-used scroll-up-line / insert copy-char-above.
map("n", "<C-y>", "dd", { desc = "Delete line" })
map("i", "<C-y>", "<esc>ddi", { desc = "Delete line" })

-- Expand / shrink selection  (JetBrains: Ctrl+W / Ctrl+Shift+W)
-- This is treesitter incremental selection, which LazyVim binds to <C-Space>
-- (expand) and <BS> (shrink). Ctrl+W is Vim's window prefix, so it is left alone;
-- these Alt aliases reuse LazyVim's own mappings via remap (no version-specific
-- treesitter API), so <C-Space>/<BS> keep working too.
map("n", "<A-w>", "<C-space>", { remap = true, desc = "Expand selection" })
map("x", "<A-w>", "<C-space>", { remap = true, desc = "Expand selection" })
map("x", "<A-S-w>", "<BS>", { remap = true, desc = "Shrink selection" })

-- Change case of selection  (JetBrains: Ctrl+Shift+U) -> a case-style menu.
-- Vim also changes a selection's case natively (u lower, U upper, ~ toggle), and
-- text-case.nvim exposes each style directly on the selection (gzc camelCase,
-- gzs snake_case, gzp PascalCase, gzn CONSTANT, gzu UPPER, gzl lower, gzd dash,
-- gzt Title). This binds the JetBrains key to a picker of them (snacks-backed
-- via vim.ui.select). Each choice re-selects the range (gv) and applies the key.
local case_items = {
  { label = "Toggle case", keys = "gv~" },
  { label = "UPPER CASE", keys = "gvgzu" },
  { label = "lower case", keys = "gvgzl" },
  { label = "snake_case", keys = "gvgzs" },
  { label = "camelCase", keys = "gvgzc" },
  { label = "PascalCase", keys = "gvgzp" },
  { label = "CONSTANT_CASE", keys = "gvgzn" },
  { label = "dash-case", keys = "gvgzd" },
  { label = "Title Case", keys = "gvgzt" },
}
map("x", "<C-S-u>", function()
  -- Finalise the visual selection (sets '< '> so gv can restore it), then pick.
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<Esc>", true, false, true), "nx", false)
  vim.ui.select(case_items, {
    prompt = "Change case",
    format_item = function(item)
      return item.label
    end,
  }, function(choice)
    if choice then
      vim.api.nvim_feedkeys(choice.keys, "m", false)
    end
  end)
end, { desc = "Change case (menu)" })

-- Terminal toggle  (JetBrains: Ctrl+T -> ActivateTerminalToolWindow)
map("n", "<C-t>", function()
  Snacks.terminal(nil, { cwd = LazyVim.root() })
end, { desc = "Terminal (Root Dir)" })
map("t", "<C-t>", "<cmd>close<cr>", { desc = "Hide Terminal" })

-- Navigate Back / Forward  (JetBrains: Shift+Alt+Left/Right) via the jumplist
map("n", "<A-S-Left>", "<C-o>", { desc = "Jump back" })
map("n", "<A-S-Right>", "<C-i>", { desc = "Jump forward" })

-- Rename symbol  (JetBrains: Ctrl+Alt+R -> RenameElement)
map("n", "<C-A-r>", vim.lsp.buf.rename, { desc = "Rename symbol (LSP)" })
