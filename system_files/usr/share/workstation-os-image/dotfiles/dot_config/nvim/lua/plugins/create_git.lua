-- Git parity beyond LazyVim's gitsigns + snacks(lazygit): diffview for visual
-- side-by-side diff / file history / 3-way merge / branch review, and
-- git-conflict for inline conflict resolution.
local Path = require("util.path")

-- Diffview's index buffers keep a normal buftype (so `:w` stages), so nvim starts LSP on
-- them. lspconfig root_dir helpers walk upward from the `diffview://` name, degenerate to
-- the cwd, and servers get workspace "file://." -- oxlint and tailwindcss reject it, and
-- nvim 0.12 raises the failed initialize as an error popup. LSP is useless in a diff anyway.
local function block_lsp_in_diffview_buffers()
  local start_client = vim.lsp.start
  vim.lsp.start = function(config, opts)
    if vim.api.nvim_buf_get_name(opts and opts.bufnr or 0):find("^diffview://") then
      return
    end
    return start_client(config, opts)
  end
end

local branch_review_tab

-- Round trip: outside the review it opens/focuses it, inside it closes it,
-- so <leader>gb always alternates between code and branch review.
local function toggle_branch_review()
  if branch_review_tab and vim.api.nvim_tabpage_is_valid(branch_review_tab) then
    if vim.api.nvim_get_current_tabpage() == branch_review_tab then
      vim.cmd("DiffviewClose")
      branch_review_tab = nil
      return
    end
    vim.api.nvim_set_current_tabpage(branch_review_tab)
    require("diffview.actions").focus_files()
    return
  end
  vim.cmd("DiffviewOpen main...HEAD")
  branch_review_tab = vim.api.nvim_get_current_tabpage()
end

-- The jump strands the explorer on the previous file, so put its tree on the one we land on
local function edit_file_and_reveal_in_explorer()
  require("diffview.actions").goto_file_edit()
  local file = vim.api.nvim_buf_get_name(0)
  if vim.bo.buftype ~= "" or file == "" then
    return
  end
  local file_win = vim.api.nvim_get_current_win()
  Snacks.explorer.reveal({ file = file })
  vim.defer_fn(function()
    pcall(vim.api.nvim_set_current_win, file_win)
  end, 100)
end

local preview_timer = vim.uv.new_timer()

-- Debounced because holding `j` would otherwise spawn a git job per line crossed
local function preview_entry_under_cursor()
  preview_timer:start(
    60,
    0,
    vim.schedule_wrap(function()
      local view = require("diffview.lib").get_current_view()
      if not (view and view.panel:is_focused()) then
        return
      end
      local entry = view.panel:get_item_at_cursor()
      if entry and type(entry.collapsed) ~= "boolean" and entry ~= view.cur_entry then
        view:set_file(entry, false)
      end
    end)
  )
end

local function preview_entries_while_moving(panel)
  vim.api.nvim_create_autocmd("CursorMoved", {
    buffer = panel.bufid,
    callback = preview_entry_under_cursor,
  })
end

-- The panel and the diff panes hold `diffview://` buffers, so `%` never yields the real path.
local function yank_cur_diff_file(to_path)
  return function()
    local view = require("diffview.lib").get_current_view()
    local file = view and view:infer_cur_file()
    if not file then
      vim.notify("No file under cursor", vim.log.levels.INFO)
      return
    end
    local path = to_path(file.absolute_path)
    vim.fn.setreg("+", path)
    vim.notify("Copied: " .. path, vim.log.levels.INFO)
  end
end

local function stage_entry()
  require("diffview.actions").toggle_stage_entry()
end

return {
  {
    "sindrets/diffview.nvim",
    cmd = { "DiffviewOpen", "DiffviewFileHistory", "DiffviewClose" },
    init = block_lsp_in_diffview_buffers,
    keys = {
      { "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "Git diff" },
      { "<leader>gb", toggle_branch_review, desc = "Toggle branch review (main...HEAD)" },
      { "<leader>gH", "<cmd>DiffviewFileHistory %<cr>", desc = "File history" },
      { "<leader>gx", "<cmd>DiffviewClose<cr>", desc = "Close diff view" },
    },
    opts = {
      keymaps = {
        -- <leader>gs stages from the diff panes too, not only the file panel ("-"/"s"),
        -- so it matches the global <leader>gs in config/keymaps.lua
        view = {
          { "n", "<leader>gs", stage_entry, { desc = "Stage/unstage file" } },
          { "n", "<leader>fy", yank_cur_diff_file(Path.relative), { desc = "Yank file path (relative)" } },
          { "n", "<leader>fY", yank_cur_diff_file(Path.absolute), { desc = "Yank file path (absolute)" } },
        },
        file_panel = {
          { "n", "<leader>gs", stage_entry, { desc = "Stage/unstage file" } },
          { "n", "e", edit_file_and_reveal_in_explorer, { desc = "Edit the real file" } },
          { "n", "<leader>fy", yank_cur_diff_file(Path.relative), { desc = "Yank file path (relative)" } },
          { "n", "<leader>fY", yank_cur_diff_file(Path.absolute), { desc = "Yank file path (absolute)" } },
        },
      },
      hooks = {
        view_opened = function(view)
          -- Sync scroll between diff panels. The file panel stays out:
          -- scrollbind drags its cursor away while the diffs scroll.
          for _, win in ipairs(view.cur_layout.windows) do
            vim.wo[win.id].scrollbind = true
          end
          view.panel:focus()
          preview_entries_while_moving(view.panel)
        end,
      },
    },
  },
  {
    "akinsho/git-conflict.nvim",
    version = "*",
    -- Host only: git-conflict runs git eagerly on load and hangs inside a Dev
    -- Container (`dev nvim`); commits/merges are done host-side anyway, and
    -- diffview handles in-container merge viewing.
    cond = function()
      return not vim.env.NVIM_IN_CONTAINER
    end,
    event = "VeryLazy",
    opts = {},
  },
}
