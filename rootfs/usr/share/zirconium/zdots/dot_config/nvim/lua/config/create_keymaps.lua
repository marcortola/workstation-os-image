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
-- LazyVim's nvim-treesitter is on the "main" branch, which dropped the
-- incremental_selection module, so this drives core vim.treesitter directly:
-- grow to the enclosing node, remembering each range so we can shrink back.
-- Primary key is Ctrl+Space (free, terminal-safe); Alt+w is a JetBrains alias.
local ts_stack = {}

local function ts_set_visual(sr, sc, er, ec) -- 0-indexed rows/cols, ec exclusive
  if vim.fn.mode():match("^[vV\22]") then
    vim.cmd("normal! \27")
  end
  vim.api.nvim_win_set_cursor(0, { sr + 1, sc })
  vim.cmd("normal! v")
  vim.api.nvim_win_set_cursor(0, { er + 1, math.max(ec - 1, 0) })
end

local function ts_cur_sel() -- current visual range as sr,sc,er,ec (ec exclusive) or nil
  if not vim.fn.mode():match("^[vV\22]") then
    return nil
  end
  local a, b = vim.fn.getpos("v"), vim.fn.getpos(".")
  local sr, sc, er, ec = a[2] - 1, a[3] - 1, b[2] - 1, b[3] - 1
  if sr > er or (sr == er and sc > ec) then
    sr, sc, er, ec = er, ec, sr, sc
  end
  return sr, sc, er, ec + 1
end

local function ts_expand()
  local buf = vim.api.nvim_get_current_buf()
  local sr, sc, er, ec = ts_cur_sel()
  local node
  if sr then
    node = vim.treesitter.get_node({ pos = { sr, sc } })
    while node do
      local a, b, c, d = node:range()
      if a < sr or (a == sr and b < sc) or c > er or (c == er and d > ec) then
        break
      end
      node = node:parent()
    end
    ts_stack[buf] = ts_stack[buf] or {}
    table.insert(ts_stack[buf], { sr, sc, er, ec })
  else
    ts_stack[buf] = {}
    node = vim.treesitter.get_node()
  end
  if not node then
    return
  end
  local a, b, c, d = node:range()
  ts_set_visual(a, b, c, d)
end

local function ts_shrink()
  local st = ts_stack[vim.api.nvim_get_current_buf()]
  if st and #st > 0 then
    local r = table.remove(st)
    ts_set_visual(r[1], r[2], r[3], r[4])
  end
end

map({ "n", "x" }, "<C-Space>", ts_expand, { desc = "Expand selection" })
map({ "n", "x" }, "<A-w>", ts_expand, { desc = "Expand selection" })
map("x", "<A-S-w>", ts_shrink, { desc = "Shrink selection" })

-- Change case of selection  (JetBrains: Ctrl+Shift+U) -> text-case's gz menu.
-- text-case.nvim binds the case styles under the gz prefix and registers them
-- with which-key, so entering gz on a selection pops a proper menu: gzs snake,
-- gzc camel, gzp Pascal, gzn CONSTANT, gzu UPPER, gzl lower, gzd dash, gzt Title.
-- Ctrl+Shift+U just enters that prefix on the current selection (native u/U/~
-- also change a selection's case directly, without the menu).
map("x", "<C-S-u>", "gz", { remap = true, desc = "Change case (gz menu)" })

-- Terminal toggle  (JetBrains: Ctrl+T -> ActivateTerminalToolWindow).
-- Opens fish when the container ships it, else the default shell (bash in a
-- container, per options.lua; the host's login shell otherwise).
map("n", "<C-t>", function()
  local shell = vim.fn.executable("fish") == 1 and "fish" or nil
  Snacks.terminal(shell, { cwd = LazyVim.root() })
end, { desc = "Terminal (Root Dir)" })
map("t", "<C-t>", "<cmd>close<cr>", { desc = "Hide Terminal" })

-- Navigate Back / Forward  (JetBrains: Shift+Alt+Left/Right) via the jumplist
map("n", "<A-S-Left>", "<C-o>", { desc = "Jump back" })
map("n", "<A-S-Right>", "<C-i>", { desc = "Jump forward" })

-- Rename symbol  (JetBrains: Ctrl+Alt+R -> RenameElement)
map("n", "<C-A-r>", vim.lsp.buf.rename, { desc = "Rename symbol (LSP)" })
