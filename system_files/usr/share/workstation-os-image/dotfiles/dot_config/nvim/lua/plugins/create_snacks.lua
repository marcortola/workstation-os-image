local Path = require("util.path")

-- Shared across files/grep/explorer so noise dirs and lockfiles never show up
-- in fuzzy find, grep, or the tree. `.claude` is intentionally kept.
local exclude = {
  "node_modules",
  ".next",
  "dist",
  "build",
  ".astro",
  ".vercel",
  ".turbo",
  ".git",
  "pnpm-lock.yaml",
  "yarn.lock",
  "package-lock.json",
  ".venv",
  "venv",
  "__pycache__",
  ".pytest_cache",
  ".mypy_cache",
  ".ruff_cache",
}

-- Anchor to a path segment: the explorer matches unanchored, so ".astro" would hide *.astro files
local explorer_exclude = vim.tbl_map(function(glob)
  return "*/" .. glob
end, exclude)

-- Live grep from the root dir, seeded with the last search so it survives close/reopen
local function sticky_root_grep(opts)
  Snacks.picker.grep(vim.tbl_extend("keep", opts or {}, {
    cwd = LazyVim.root(),
    search = vim.g.last_live_grep or "",
    on_close = function(picker)
      vim.g.last_live_grep = picker.input.filter.search
    end,
  }))
end

-- Reveal in the desktop file manager. Upstream used macOS `open -R`; nautilus is
-- what this image ships (niri binds it on Mod+F) and takes --select for the
-- same effect, with xdg-open on the parent directory as the fallback.
local function reveal(item)
  if item.dir then
    vim.fn.jobstart({ "xdg-open", item.file }, { detach = true })
  elseif vim.fn.executable("nautilus") == 1 then
    vim.fn.jobstart({ "nautilus", "--select", item.file }, { detach = true })
  else
    vim.fn.jobstart({ "xdg-open", vim.fn.fnamemodify(item.file, ":h") }, { detach = true })
  end
end

local function yank_item_path(to_path)
  return function(_, item)
    if not item then
      return
    end
    local path = to_path(item.file)
    vim.fn.setreg("+", path)
    Snacks.notify.info("Copied: " .. path)
  end
end

return {
  "folke/snacks.nvim",
  keys = {
    {
      "<leader>ss",
      function()
        sticky_root_grep()
      end,
      desc = "Search Grep (Root Dir, sticky)",
    },
    {
      "<leader>fs",
      mode = "x",
      function()
        local selection = Snacks.picker.util.visual()
        local first_line = selection and selection.text:match("^[^\n]*") or ""
        sticky_root_grep({ search = vim.trim(first_line), regex = false })
      end,
      desc = "Search Selection (Root Dir)",
    },
    -- Override LazyVim default (Snacks.picker.lines) with vim's native / search
    { "<leader>sb", "/", desc = "Search forward (vim /)" },
    { "<leader>sB", "?", desc = "Search backward (vim ?)" },
    -- Disable Snacks git_diff picker; it collides with Diffview's <leader>gd (see git.lua)
    { "<leader>gd", false },
    -- Disable Snacks git_status picker; <leader>gs stages the current file (see config/keymaps.lua)
    { "<leader>gs", false },
  },
  init = function()
    -- Keep the dashboard static on pane resize; snacks' recenter-on-resize reads
    -- as a cursor "tour" every time a herdr pane is equalized.
    vim.api.nvim_create_autocmd("User", {
      group = vim.api.nvim_create_augroup("user_dashboard_no_recenter", { clear = true }),
      pattern = "SnacksDashboardOpened",
      callback = function()
        vim.schedule(function()
          pcall(vim.api.nvim_clear_autocmds, { group = "snacks_dashboard", event = { "WinResized", "VimResized" } })
        end)
      end,
    })
    -- LazyVim's snacks_picker spec installs <leader>ss as a buffer-local
    -- "LSP Symbols" mapping (via Snacks.keymap.set + has = "documentSymbol")
    -- which shadows our global grep in any LSP-attached buffer. Strip it on
    -- LspAttach and expose LSP Symbols on <leader>sy instead.
    vim.api.nvim_create_autocmd("LspAttach", {
      group = vim.api.nvim_create_augroup("user_force_grep_ss", { clear = true }),
      callback = function(ev)
        -- Snacks installs its buffer-local <leader>ss via a 100ms-debounced
        -- on_lsp; defer past that window so our overrides win.
        vim.defer_fn(function()
          if not vim.api.nvim_buf_is_valid(ev.buf) then
            return
          end
          pcall(vim.keymap.del, "n", "<leader>ss", { buffer = ev.buf })
          vim.keymap.set("n", "<leader>sy", function()
            Snacks.picker.lsp_symbols({ filter = LazyVim.config.kind_filter })
          end, { buffer = ev.buf, desc = "LSP Symbols" })
        end, 200)
      end,
    })
  end,
  opts = {
    bigfile = {
      size = 10 * 1024 * 1024, -- 10MB (default ~1.5MB disables filetype on big CSV exports)
    },
    picker = {
      actions = {
        clear_input = function(picker)
          picker.input:set("", "")
        end,
      },
      win = {
        input = {
          keys = {
            ["<C-d>"] = { "preview_scroll_down", mode = { "i", "n" } },
            ["<C-u>"] = { "preview_scroll_up", mode = { "i", "n" } },
            ["<C-x>"] = { "clear_input", mode = { "i", "n" } },
          },
        },
        list = {
          keys = {
            ["<C-d>"] = "preview_scroll_down",
            ["<C-u>"] = "preview_scroll_up",
          },
        },
        preview = {
          wo = { scroll = 5 }, -- step size for <C-d>/<C-u> in preview (lazygit-like)
        },
      },
      previewers = {
        file = {
          -- markdown preview is unstable on 0.11; sqlite (.db) is binary and
          -- dumps raw bytes (see the filetype mapping in config/options.lua).
          ft_blacklist = { "markdown", "sqlite" },
        },
      },
      formatters = {
        file = {
          filename_first = true, -- filename column leftmost, easier to scan same-file matches
        },
      },
      sources = {
        files = {
          hidden = true,
          ignored = true,
          exclude = exclude,
        },
        grep = {
          hidden = true,
          ignored = true,
          exclude = exclude,
        },
        explorer = {
          hidden = true, -- Show hidden files (H toggle)
          ignored = true, -- Show ignored files (I toggle)
          exclude = explorer_exclude,
          layout = { preview = "main" },
          actions = {
            explorer_open = {
              action = function(_, item)
                if item then
                  reveal(item)
                end
              end,
            },
            copy_relative_path = { action = yank_item_path(Path.relative) },
            copy_absolute_path = { action = yank_item_path(Path.absolute) },
            grep_root = {
              action = function()
                Snacks.picker.grep()
              end,
            },
            -- Toggle stage/unstage of the file under cursor (mirrors <leader>gs)
            git_stage = {
              action = function(picker, item)
                if not item then
                  return
                end
                local function toggle(staged)
                  local cmd = staged and { "git", "restore", "--staged", item.file } or { "git", "add", item.file }
                  Snacks.picker.util.cmd(cmd, function()
                    require("snacks.explorer.git").refresh(picker:cwd())
                    require("snacks.explorer.tree"):refresh(picker:cwd())
                    require("snacks.explorer.actions").update(picker, { refresh = true })
                  end, { cwd = picker:cwd() })
                end
                if item.status then
                  return toggle(item.status:sub(2) == " ")
                end
                if not item.dir then
                  return
                end
                -- Open dirs carry no status (explorer.lua only sets it on closed dirs), resolve it from git
                Snacks.picker.util.cmd({ "git", "status", "--porcelain", "--", item.file }, function(out)
                  local any, all_staged = false, true
                  for line in table.concat(out, "\n"):gmatch("[^\n]+") do
                    any = true
                    if line:sub(2, 2) ~= " " then
                      all_staged = false
                      break
                    end
                  end
                  if any then
                    toggle(all_staged)
                  end
                end, { cwd = picker:cwd() })
              end,
            },
          },
          win = {
            list = {
              keys = {
                ["f"] = "focus_input",
                ["<C-o>"] = "explorer_open",
                ["<leader>fy"] = "copy_relative_path",
                ["<leader>fY"] = "copy_absolute_path",
                ["<leader>S"] = "grep_root",
                ["gs"] = { "git_stage", desc = "Stage/unstage file" },
                ["<leader>gs"] = { "git_stage", desc = "Stage/unstage file" },
              },
            },
          },
        },
      },
    },
  },
}
